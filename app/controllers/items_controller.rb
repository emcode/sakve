class ItemsController < ApplicationController

  helper_method :selection

  # GET /items
  # GET /items.xml
  def index
    authorize! :read, Item
    @global_folder = Folder.global_root
    @user_folder = Folder.user_root(current_user)
    @shared_folders = Folder.shared_for(current_user)
    @current_folder = Folder.where(id: params[:folder]).first || (params[:folder] == 'user' ? @user_folder : @global_folder)
    @current_folder = nil if params[:folder] == 'shared'

    @item = Item.new(folder: @current_folder, user: current_user)

    if @current_folder
      @subfolders = @current_folder.subfolders.scoped
      @items = Item.where(folder_id: @current_folder.try(:id))
    elsif params[:folder] == 'shared'
      @subfolders = @shared_folders
      @items = Item.shared_for(current_user)
    end

    if params.has_key?(:sort)
      column = (params[:sort][:column] || :name).to_sym
      order = (params[:sort][:dir] || :asc).to_sym
      if [:name, :size, :date].include?(column)
        @items = @items.sort_by { |i| i.send(column) }
        @items.reverse! if order == :desc
      end
      if [:name, :date].include?(column)
        @subfolders = @subfolders.sort_by { |i| i.send(column) }
        @subfolders.reverse! if order == :desc
      end
    end

    @folder = Folder.new parent: @current_folder, user: current_user, global: @current_folder.try(:global)

    respond_to do |format|
      format.html { render layout: !request.xhr? }
    end
  end

  def multiupload
    @global_folder = Folder.global_root
    @user_folder = Folder.user_root(current_user)
    @shared_folders = Folder.shared_for(current_user)
    @current_folder = Folder.where(id: params[:folder]).first || (params[:folder] == 'user' ? @user_folder : @global_folder)
    @current_folder = nil if params[:folder] == 'shared'

    @item = Item.new(folder: @current_folder, user: current_user)

    respond_to do |format|
      format.html { render layout: !request.xhr? }
    end
  end

  # GET /items/1.json
  def show
    @item = Item.find(params[:id])
    authorize! :read, @item

    respond_to do |format|
      format.json  { render json: @item }
      format.js
    end
  end

  def download
    @item = Item.find(params[:id])
    authorize! :read, @item

    send_file @item.object.path(params[:style]),
      filename: @item.name_for_download(params[:format]),
      content_type: @item.content_type(params[:style]),
      disposition: 'inline'
  rescue CanCan::AccessDenied
    send_data Item.access_denied_image(params[:style]), type: 'image/png'
  end

  # GET /items/1/edit
  def edit
    @item = Item.find(params[:id])
    authorize! :update, @item

    respond_to do |format|
      format.js
    end
  end

  # POST /items
  # POST /items.xml
  def create
    @item = Item.new
    @item.prevent_processing!
    @item.attributes = params[:item]
    @item.user = current_user

    authorize! :create, @item

    respond_to do |format|
      if @item.save
        format.html { redirect_to(items_path, notice: I18n.t('create.success') ) }
        format.json { render action: :create, status: :ok, location: @item }
      else
        format.html { render action: "new" }
        format.json { render action: :create, status: :unprocessable_entity }
      end
    end
  end

  # PUT /items/1
  # PUT /items/1.xml
  def update
    @item = Item.find(params[:id])
    authorize! :update, @item

    respond_to do |format|
      if @item.update_attributes(params[:item])
        format.html { redirect_to(items_path, notice: I18n.t('update.success') ) }
        format.js
      else
        format.html { render action: "edit" }
        format.js
      end
    end
  end

  def change_folder
    item = Item.find(params[:item_id])
    folder_id = params[:folder_id]
    item.update_attributes(folder_id: folder_id)

    render nothing: true
  end

  def share
    @item = Item.find(params[:id])
    authorize! :share, @item


    if request.put?
      params[:with] ||= {}

      user_ids = params[:with][:users].try(:map, &:to_i)
      @item.users = User.where(id: user_ids)

      group_ids = params[:with][:groups].try(:map, &:to_i)
      @item.groups = Group.where(id: group_ids)
    end

    respond_to do |format|
      format.js
    end
  end

  # DELETE /items/1
  # DELETE /items/1.xml
  def destroy
    @item = Item.find(params[:id])
    authorize! :destroy, @item
    @item.destroy

    respond_to do |format|
      format.html { redirect_to :back, notice: I18n.t('delete.success') }
      format.js
    end
  end

  def bulk_download

    if params[:token]
      @selection = current_user.selection_downloads.where(id: params[:token]).first
    else
      @selection = current_user.selection_downloads.create(selection)
    end

    respond_to do |format|
      format.js
      format.zip
    end
  end

  def bulk_edit
    @folders = Folder
      .accessible_by(current_ability, :update)
      .where( id: selection[:fids] )
    @items = Item
      .accessible_by(current_ability, :update)
      .where( id: selection[:ids] )


    respond_to do |format|
      format.js
    end
  end

  def bulk_update
    @folders = Folder
      .accessible_by(current_ability, :update)

    @items = Item
      .accessible_by(current_ability, :update)

    Folder.transaction do
      if (@ferror = @folders.bulk(selection)) === true
        @ierror = @items.bulk( selection )
        raise ActiveRecord::Rollback unless @ierror === true
      end
    end

    respond_to do |format|
      format.js
    end


  end

  def bulk_destroy
    @folders = Folder
      .accessible_by(current_ability, :update)
      .where( id: selection[:fids] )
      .destroy_all
    @items = Item
      .accessible_by(current_ability, :update)
      .where( id: selection[:ids] )
      .destroy_all

    respond_to do |format|
      format.js
    end
  end

  private



end
