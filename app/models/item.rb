class Item < ActiveRecord::Base
  belongs_to :user
  has_many :item_tags
  has_many :tags, through: :item_tags

  has_attached_file :object, 
    styles: Proc.new {|object| object.instance.item_styles } ,
    processors: [:item_processor],
    path: ':partition/:class/:id/:style/:filename',
    url: '/:class/:id/download/:style/:filename'

  before_save :fix_mime_type, :save_tags

  attr_accessible :name, :object, :type, :user_id, :tags

  validates :object, attachment_presence: true

  def item_styles
    styles = {
      thumb: ['128x128#', :png],
    }
    if video?
      styles[:preview] = ['640x480>', :mp4]
      styles[:flash] = ['640x480>', :flv]
    elsif presentation?
      styles[:preview] = ['200', :pdf]
    elsif image? or pdf_document?
      styles[:preview] = ['640x480>', :png]
    end
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

  def fix_mime_type(force = false)
    if force || object_content_type == 'application/octet-stream'
      object_content_type = Paperclip::ContentTypeDetector.new(object.path).detect
    end
  end

  def video?
    object_content_type.match /^video/
  end

  def image?
    object_content_type.match /^image/
  end

  def audio?
    object_content_type.match /^audio/
  end

  def document?
    object_content_type.match /(word|excel|powerpoint|officedocument|opendocument)/
  end

  def presentation?
    object_content_type.match /(powerpoint|presentation)$/
  end

  def spreadsheet?
    object_content_type.match /(excel|spreadsheet)$/
  end

  def text_document?
    document? and object_content_type.match /word|text/
  end

  def pdf_document?
    object_content_type.match /pdf$/
  end

  def archive?
    object_content_type.match /(bzip2$|[gl]zip$|zip$|lzma$|lzop$|xz$|commpress|archive|diskimage$)/
  end

  def webpage?
   text_file? and object_content_type.match /(css|js|html|xml)/
  end

  def text_file?
    object_content_type.match /^text/
  end

  def icon_name
    if video?
      :video
    elsif audio?
      :audio
    elsif image?
      :image
    elsif archive?
      :archive
    elsif presentation?
      :presentation
    elsif spreadsheet?
      :spreadsheet
    elsif text_document?
      :text_document
    elsif webpage?
      :webpage
    elsif text_file?
      :text
    else
      :none
    end
  end

  protected

  def save_tags
    if @tags
      item_tags.destroy_all
      @tags.split(',').map(&:strip).each do |tag|
        t = Tag.where(name: tag).first || Tag.create(name: tag)  
        self.item_tags.create(tag_id: t.id)
      end

    end
  end
end
