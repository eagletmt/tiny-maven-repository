class ArtifactsController < ApplicationController

  skip_before_action :verify_authenticity_token, only: %i(publish)

  def index
    unless request.original_fullpath.end_with?('/')
      return redirect_to "#{request.original_fullpath}/"
    end

    @files = files(Rails.application.config.artifact_root_path)
  end

  def show
    if request.head?
      status = if artifact_path.exist?
                 200
               else
                 404
               end
      head status, connection: 'close'
      return
    end

    path = artifact_path
    if path.try(:directory?)
      unless request.original_fullpath.end_with?('/')
        return redirect_to "#{request.original_fullpath}/"
      end

      @files = files(path)
      render :index
    else
      send_file(path)
    end
  rescue ActionController::MissingFile
    render text: "File Not Found\n", status: 404
  end

  def publish
    path = artifact_path
    open_for_writing(path) do |outs|
      IO.copy_stream(request.body_stream, outs)
    end

    render nothing: true, status: 204
  rescue
    render text: 'Bad Request', status: 400
  end

  def delete
    # TODO: too much logic in controllers!
    path = artifact_path
    # path is something like "/path/to/com/cookpad/android/pantryman/1.0.0"

    # remove it from metadata first
    version = path.basename.to_s
    unless /\d/ =~ version
      return render text: "Bad Request: #{path}", status: 400
    end

    artifacts_dir = path.parent

    metadata_file = artifacts_dir.join('maven-metadata.xml')
    artifact = Artifact.new(File.read(metadata_file))
    artifact.remove_version(version)
    if artifact.empty?
      FileUtils.rmtree(artifacts_dir)
    else
      artifact.save(metadata_file)

      FileUtils.rmtree(path)
    end

    redirect_to root_path, notice: 'artifact deleted'
  end

  private

  def files(dir)
    Dir.foreach(dir).sort.find_all do |item|
      !item.start_with?('.')
    end
  end

  # @return [Pathname]
  def artifact_path
    root = Rails.application.config.artifact_root_path
    path = root.join(params.require(:artifact_path))
    path.cleanpath.to_s.start_with?(root.to_s + "/") ? path : nil
  end

  def open_for_writing(path, &block)
    FileUtils.mkdir_p(path.dirname)
    File.open(path, "wb", &block)
  end
end
