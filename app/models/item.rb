class Item < ActiveRecord::Base
  @@statuses = %w(unprocessed processing finished).map(&:to_sym).freeze

  include Sakve::ItemTypes
  include ItemBulkActions
  include ConvertStatus

  belongs_to :user
  belongs_to :folder, touch: true
  has_many :item_tags, include: :tag, dependent: :destroy
  has_many :tags, through: :item_tags
  has_many :shares, as: :resource
  has_many :users,  through: :shares, source: :collaborator, source_type: 'User'
  has_many :groups,  through: :shares, source: :collaborator, source_type: 'Group'

  scope :shared_for_user, lambda {|user| includes(:users).where(shares: {collaborator_id: user.id})}
  scope :shared_for_groups, lambda {|user| includes(:groups).where(shares: {collaborator_id: user.groups})}

  scope :shared_for, lambda { |user|
    joins(:shares)
      .group("`#{table_name}`.`id`")
      .where(%{(`#{Share.table_name}`.`collaborator_type` = 'User'
          AND `#{Share.table_name}`.`collaborator_id` = ?)
        OR (`#{Share.table_name}`.`collaborator_type` = 'Group'
          AND `#{Share.table_name}`.`collaborator_id` IN (#{user.groups.select("`#{user.groups.table_name}`.`id`").to_sql}))}.gsub($/, ''), user)
      .where("`#{table_name}`.`user_id` != ?", user.id)
  }

  scope :allowed_for, lambda { |user|
    includes(:folder)
    .where(%{`#{table_name}`.user_id = :user
      OR `#{Folder.table_name}`.`user_id` = :user
      OR `#{Folder.table_name}`.`global`
      OR `#{table_name}`.`id` IN (#{shared_for(user).select("`items`.`id`").to_sql})
      OR `#{Folder.table_name}`.`id` IN (#{Folder.shared_for(user).select("`folders`.`id`").to_sql})}.gsub($/, ''),
      user: user)
  }

  has_attached_file :object,
    styles: proc {|object| object.instance.item_styles } ,
    processors: [:item_processor],
    path: ':partition/:class/:id/:style/:filename',
    url: '/:class/:id/download/:style/:name.:extension'

  before_validation :fix_mime_type, :default_name
  before_create :save_tags
  after_commit :async_reprocess!

  attr_accessible :name, :object, :type, :user_id, :user, :tags, :folder_id, :folder,
    :object_file_name

  validates :object,
    attachment_presence: true,
    attachment_content_type: { content_type: /.*/i }

  validates :folder_id, presence: true

  def size; object_file_size; end
  def date; updated_at; end

  def async_reprocess!
    ItemProcessWorker.perform_async(self.id) if status_unprocessed?
  end

  def reprocess!
    self.status_processing!
    self.object.reprocess!
    self.status_finished!
  end

  def public?
    self.folder.global?
  end

  def prevent_processing!
    self.object.post_processing = false
  end

  def shared_for? user
    users.exists?(user) || user.groups.map{|g| groups.exists?(g) }.inject{|a,b| a || b} || folder.shared_for?(user)
  end


  def content_type(style = nil)
    style ||= :original
    MIME::Types.type_for(Item.last.object.path(style)).first.try(:content_type)
  end

  def item_styles
    styles = {
      thumb: ['128x128#', :png]
    }
    if video?
      styles[:mp4] = ['640x480>', :mp4]
      styles[:flash] = ['640x480>', :flv]
      styles[:preview] = ['640x480>', :png]
    elsif image? or document?
      styles[:preview] = ['640x480>', :png]
    end
    styles[:slides] = ['200', :pdf] if presentation?
    styles
  end

  def thumb
    object.url(:thumb)
  end

  alias :tags_list :tags

  def tags=(value)
    @tags = value
  end

  def tags
    @tags || tags_list.join(', ')
  end

  def self.search_by_tags(*tags)
    tags = tags.flatten
    return [] if tags.empty?
    assoc = self.reflect_on_association(:tags)
    self.joins(:tags).
      where(assoc.table_name.to_sym => {name: tags}).
      group("#{table_name}.id").
      having("COUNT(`#{assoc.table_name}`.`#{assoc.association_primary_key}`) = ?", tags.size)
  end

  def self.search_by_name(*words)
    words = words.flatten
    return [] if words.empty?
    words.inject(self) do |result, w|
      result.where("`#{table_name}`.`name` LIKE ?", "%#{w}%")
    end
  end

  def self.search(query)
    words = query.query_tokenize
    tags = query.query_tokenize(:tag)
    self.search_by_tags(tags) | self.search_by_name(words)
  end

  def self.access_denied_image(style)

  end

  def extension
    File.extname(object_file_name).gsub('.', '')
  end

  def name_for_download(extension = nil, increment = nil)
    extension = File.extname(object.original_filename).gsub(/^\./, '') if extension.nil?
    "#{name.parameterize}#{".#{increment}" unless increment.nil?}.#{extension}"
  end

  def check_user_limit(user)
    return true if user.max_upload_size.nil?
    return true if user.files_uploaded_size + object_file_size < user.max_upload

    errors.add :item, 'przekroczono dostępny transfer'
    false
  end

  protected

  def file_for_transfer
    self.object
  end

  def default_name
    self.name ||= File.basename(object_file_name, '.*').titleize if object?
  end

  def save_tags
    if @tags
      tag_list = @tags.split(',').map(&:strip)
      item_tags.each do |item_tag|
        unless tag_list.include? item_tag.name
          item_tag.destroy
        end
      end
      tag_list.each do |tag|
        t = Tag.where(name: tag).first || Tag.create(name: tag)
        self.item_tags.create(tag_id: t.id)
      end
    end
  end
end
