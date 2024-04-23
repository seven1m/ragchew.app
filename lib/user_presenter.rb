class UserPresenter
  NET_LOGGER_FAKE_VERSION = 'v3.1.7L'

  def initialize(user)
    @user = user
  end

  def name_for_monitoring
    name = name_for_chat
    # NOTE: must use a real version here or UnsubscribeFromNet won't work :-(
    name + " - #{NET_LOGGER_FAKE_VERSION}"
  end

  alias name_for_logging name_for_monitoring

  def name_for_chat
    name = @user.call_sign
    name += '-' + @user.first_name unless @user.first_name.to_s.strip.empty?
    name.upcase
  end
end

