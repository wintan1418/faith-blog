# frozen_string_literal: true

# brethreign.com/b/<code>/<username>: the short link printed on a shared
# image and in its QR code. <code> is the breath's id in base 36; the
# optional username is who shared it, passed on as ?ref= (ShareReferral
# decides whether it counts). Unknown codes go to the home page.
class ShortLinksController < ApplicationController
  def show
    post = Post.find_by(id: params[:code].to_i(36))
    return redirect_to(root_path) unless post&.visible_to?(nil)

    redirect_to post_path(post, ref: params[:ref].presence), status: :found
  end
end
