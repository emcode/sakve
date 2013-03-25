class ItemsController < ApplicationController

  layout "standard"
  before_filter :create_new_folder

  # GET /items
  # GET /items.xml
  def index
    authorize! :read, Item
    @global_folder = Folder.global_root
    @user_folder = Folder.user_root(current_user)
    @current_folder ||= params[:folder] == 'user' ? @user_folder : @global_folder

    @item = Item.new(folder: @current_folder, user: current_user)
    @items = Item.where(folder_id: @current_folder.try(:id)) 

    respond_to do |format|
      format.html do
        if params[:partial]
          render @items
        else
          render
        end
      end
      format.xml  { render xml: @items }
    end
  end

  # GET /items/1.json
  def show
    @item = Item.find(params[:id])
    authorize! :read, @item

    respond_to do |format|
      format.json  { render json: @item }
    end
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
    @item = Item.new(params[:item])
    @item.user = current_user

    authorize! :create, @item

    respond_to do |format|
      if @item.save
        format.html { redirect_to(items_path, notice: I18n.t('create.success') ) }
        format.json  { render json: @item, status: :created, location: @item }
      else
        format.html { render action: "new" }
        format.json  { render json: @item.errors, status: :unprocessable_entity }
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

  def download 
    authorize! :menage, :all
    @item = Item.find(params[:id])

    send_file @item.object.path(params[:style])
  end

  protected

  def create_new_folder
    @current_folder = Folder.where(id: params[:folder]).first
    @folder = Folder.new parent: @current_folder, user: current_user
  end
end
