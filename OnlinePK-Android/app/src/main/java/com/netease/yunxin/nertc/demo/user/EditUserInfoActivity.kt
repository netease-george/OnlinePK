/*
 *  Copyright (c) 2021 NetEase, Inc.  All rights reserved.
 *  Use of this source code is governed by a MIT license that can be found in the LICENSE file
 */

package com.netease.yunxin.nertc.demo.user

import android.os.Bundle
import android.text.Editable
import android.text.TextUtils
import android.text.TextWatcher
import android.view.View
import android.view.View.OnFocusChangeListener
import android.widget.EditText
import com.blankj.utilcode.util.ToastUtils
import com.netease.yunxin.nertc.demo.R
import com.netease.yunxin.nertc.demo.basic.BaseActivity
import com.netease.yunxin.nertc.demo.basic.StatusBarConfig
import com.netease.yunxin.nertc.demo.user.UserCenterService
import com.netease.yunxin.nertc.module.base.ModuleServiceMgr

class EditUserInfoActivity : BaseActivity() {
    private val service: UserCenterService = ModuleServiceMgr.instance.getService(
        UserCenterService::class.java
    )
    private var currentUser: UserModel? = null
    private var lastNickname: String? = null
    private var etNickname: EditText? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_edit_user_info)
        paddingStatusBarHeight(findViewById(R.id.cl_root))
        currentUser = service.currentUser
        lastNickname = currentUser!!.nickname
        initViews()
    }

    private fun initViews() {
        etNickname = findViewById(R.id.et_nick_name)
        etNickname?.setText(currentUser!!.nickname)
        val close = findViewById<View>(R.id.iv_back)
        close.setOnClickListener { v: View? -> finish() }
        val clear = findViewById<View>(R.id.iv_clear)
        clear.setOnClickListener { v: View? -> etNickname?.setText("") }
        etNickname?.onFocusChangeListener = OnFocusChangeListener { v: View?, hasFocus: Boolean ->
            val visible = hasFocus && !TextUtils.isEmpty(etNickname?.text.toString())
            clear.visibility = if (visible) View.VISIBLE else View.INVISIBLE
        }
        etNickname?.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence, start: Int, before: Int, count: Int) {
                clear.visibility = if (s.length > 0) View.VISIBLE else View.INVISIBLE
            }

            override fun afterTextChanged(s: Editable) {}
        })
    }

    private fun doForUpdatingUserModel(newNickname: String) {
        if (TextUtils.isEmpty(newNickname)) {
            ToastUtils.showShort(getString(R.string.app_user_info_update_failed))
            return
        }
        if (newNickname != lastNickname) {
            currentUser!!.nickname = newNickname
            service.updateUserInfo(currentUser!!, object : CommonUserNotify() {
                override fun onUserInfoUpdate(model: UserModel?) {
                    ToastUtils.showShort(getString(R.string.app_user_info_update_success))
                }

                override fun onError(exception: Throwable?) {
                    ToastUtils.showShort(getString(R.string.app_user_info_update_failed))
                }
            })
        }
    }

    override fun finish() {
        // 关闭页面前检查用户昵称决定是否更新
        doForUpdatingUserModel(etNickname!!.text.toString())
        super.finish()
    }

    override fun provideStatusBarConfig(): StatusBarConfig? {
        return StatusBarConfig.Builder()
            .statusBarDarkFont(false)
            .build()
    }
}