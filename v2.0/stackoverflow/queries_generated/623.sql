-- {"query": "623.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3280} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.upvotes,
        u.downvotes,
        u.views,
        row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where coalesce(nullif(trim(u.displayname), ''), 'Anonymous') is not null
),
top_recent as (
    select *
    from recent_users
    where rn <= 5000
),
user_badge_agg as (
    select
        b.userid,
        count(*) as badge_count,
        sum(case when b.class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_posts as (
    select
        p.id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.favoritecount,
        p.answercount,
        p.title,
        p.tags,
        coalesce(p.acceptedanswerid, -1) as acceptedanswerid
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select
        p.id,
        p.parentid,
        p.owneruserid,
        p.score,
        p.creationdate
    from posts p
    where p.posttypeid = 2
),
question_activity as (
    select
        q.owneruserid as user_id,
        count(*) as questions,
        sum(case when q.score > 0 then 1 else 0 end) as questions_pos,
        sum(case when q.score < 0 then 1 else 0 end) as questions_neg,
        sum(coalesce(q.viewcount,0)) as total_views,
        sum(coalesce(q.favoritecount,0)) as total_favs,
        avg(nullif(q.viewcount,0)) as avg_views_nonzero,
        count(distinct case when q.acceptedanswerid > 0 then q.id end) as accepted_questions
    from question_posts q
    group by q.owneruserid
),
answer_activity as (
    select
        a.owneruserid as user_id,
        count(*) as answers,
        sum(case when a.score > 0 then 1 else 0 end) as answers_pos,
        sum(case when a.score < 0 then 1 else 0 end) as answers_neg,
        max(a.score) as best_answer_score,
        min(a.score) as worst_answer_score
    from answer_posts a
    group by a.owneruserid
),
accepted_answers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers_count
    from answer_posts a
    where exists (
        select 1
        from question_posts q
        where q.acceptedanswerid = a.id
    )
    group by a.owneruserid
),
tag_exploded as (
    select
        q.id as question_id,
        q.owneruserid as user_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from question_posts q
    where q.tags is not null and length(q.tags) > 2
),
user_top_tag as (
    select user_id, tag, count(*) as tag_count,
           row_number() over (partition by user_id order by count(*) desc, tag) as tag_rn
    from tag_exploded
    group by user_id, tag
),
votes_agg as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upmods_cast,
        count(*) filter (where v.votetypeid = 3) as downmods_cast,
        count(*) filter (where v.votetypeid = 5) as favorites_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from votes v
    where v.userid is not null
    group by v.userid
),
post_close_events as (
    select
        ph.postid,
        max(ph.creationdate) as last_close_event_date,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_date,
        max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_date,
        max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
user_close_stats as (
    select
        coalesce(q.owneruserid, a.owneruserid) as user_id,
        count(distinct case when ce.last_closed_date is not null then ce.postid end) as posts_closed,
        count(distinct case when ce.last_reopened_date is not null then ce.postid end) as posts_reopened
    from post_close_events ce
    left join question_posts q on q.id = ce.postid
    left join answer_posts a on a.id = ce.postid
    group by coalesce(q.owneruserid, a.owneruserid)
),
question_answer_join as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        a.owneruserid as answerer_id,
        a.id as answer_id,
        a.score as answer_score,
        a.creationdate as answer_date,
        case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted
    from question_posts q
    join answer_posts a on a.parentid = q.id
),
user_interactions as (
    select
        qa.answerer_id as user_id,
        count(*) as answers_to_others,
        count(*) filter (where qa.asker_id = qa.answerer_id) as self_answers,
        count(*) filter (where qa.is_accepted = 1) as accepted_given,
        avg(qa.answer_score::numeric) as avg_answer_score
    from question_answer_join qa
    group by qa.answerer_id
),
question_time_bins as (
    select
        q.owneruserid as user_id,
        date_trunc('month', q.creationdate) as month_bucket,
        count(*) as questions_in_month
    from question_posts q
    group by q.owneruserid, date_trunc('month', q.creationdate)
),
question_time_window as (
    select
        user_id,
        month_bucket,
        questions_in_month,
        sum(questions_in_month) over (partition by user_id order by month_bucket rows between 2 preceding and current row) as rolling_3mo_questions
    from question_time_bins
),
ranked_users as (
    select
        tr.user_id,
        tr.displayname,
        tr.reputation,
        tr.location,
        tr.creationdate,
        tr.upvotes,
        tr.downvotes,
        tr.views,
        ua.badge_count,
        ua.gold_count,
        ua.silver_count,
        ua.bronze_count,
        ua.last_badge_date,
        qa.questions,
        qa.questions_pos,
        qa.questions_neg,
        qa.total_views,
        qa.total_favs,
        qa.avg_views_nonzero,
        qa.accepted_questions,
        aa.answers,
        aa.answers_pos,
        aa.answers_neg,
        aa.best_answer_score,
        aa.worst_answer_score,
        coalesce(ac.accepted_answers_count, 0) as accepted_answers_count,
        v.upmods_cast,
        v.downmods_cast,
        v.favorites_cast,
        v.bounty_events,
        v.bounty_amount_total,
        ucs.posts_closed,
        ucs.posts_reopened,
        ui.answers_to_others,
        ui.self_answers,
        ui.accepted_given,
        ui.avg_answer_score,
        utt.tag as top_tag,
        qtw.rolling_3mo_questions,
        dense_rank() over (
            order by
                coalesce(aa.answers,0) + coalesce(qa.questions,0) desc,
                coalesce(ua.badge_count,0) desc,
                tr.reputation desc
        ) as activity_rank
    from top_recent tr
    left join user_badge_agg ua on ua.userid = tr.user_id
    left join question_activity qa on qa.user_id = tr.user_id
    left join answer_activity aa on aa.user_id = tr.user_id
    left join accepted_answers ac on ac.user_id = tr.user_id
    left join votes_agg v on v.user_id = tr.user_id
    left join user_close_stats ucs on ucs.user_id = tr.user_id
    left join user_interactions ui on ui.user_id = tr.user_id
    left join (
        select user_id, tag
        from user_top_tag
        where tag_rn = 1
    ) utt on utt.user_id = tr.user_id
    left join lateral (
        select qtw.rolling_3mo_questions
        from question_time_window qtw
        where qtw.user_id = tr.user_id
        order by qtw.month_bucket desc
        limit 1
    ) qtw on true
),
topk as (
    select *
    from ranked_users
    where coalesce(answers,0) + coalesce(questions,0) > 0
),
duplicates_and_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as regular_links
    from postlinks pl
    group by pl.postid
),
user_link_stats as (
    select
        coalesce(q.owneruserid, a.owneruserid) as user_id,
        sum(coalesce(dl.duplicate_links,0)) as dup_links_user,
        sum(coalesce(dl.regular_links,0)) as reg_links_user
    from duplicates_and_links dl
    left join question_posts q on q.id = dl.postid
    left join answer_posts a on a.id = dl.postid
    group by coalesce(q.owneruserid, a.owneruserid)
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        avg(c.score::numeric) as avg_comment_score,
        max(c.score) as max_comment_score,
        sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_comments
    from comments c
    where c.userid is not null
    group by c.userid
),
final as (
    select
        tk.user_id,
        tk.displayname,
        tk.reputation,
        tk.location,
        tk.creationdate,
        tk.upvotes,
        tk.downvotes,
        tk.views,
        tk.badge_count,
        tk.gold_count,
        tk.silver_count,
        tk.bronze_count,
        tk.last_badge_date,
        tk.questions,
        tk.questions_pos,
        tk.questions_neg,
        tk.total_views,
        tk.total_favs,
        tk.avg_views_nonzero,
        tk.accepted_questions,
        tk.answers,
        tk.answers_pos,
        tk.answers_neg,
        tk.best_answer_score,
        tk.worst_answer_score,
        tk.accepted_answers_count,
        tk.upmods_cast,
        tk.downmods_cast,
        tk.favorites_cast,
        tk.bounty_events,
        tk.bounty_amount_total,
        tk.posts_closed,
        tk.posts_reopened,
        tk.answers_to_others,
        tk.self_answers,
        tk.accepted_given,
        tk.avg_answer_score,
        tk.top_tag,
        tk.rolling_3mo_questions,
        tk.activity_rank,
        uls.dup_links_user,
        uls.reg_links_user,
        cs.comments_made,
        cs.avg_comment_score,
        cs.max_comment_score,
        cs.thanks_comments,
        coalesce(tk.answers,0) * 1.0 / nullif(coalesce(tk.answers_pos,0) + coalesce(tk.answers_neg,0), 0) as ans_to_scored_ratio,
        case
            when coalesce(tk.answers,0) = 0 then null
            else round((coalesce(tk.accepted_given,0)::numeric / nullif(coalesce(tk.answers,0),0)) * 100, 2)
        end as accepted_rate_pct,
        case
            when coalesce(tk.questions,0) = 0 then null
            else round((coalesce(tk.accepted_questions,0)::numeric / nullif(coalesce(tk.questions,0),0)) * 100, 2)
        end as questions_accept_pct,
        case
            when coalesce(tk.upmods_cast,0) + coalesce(tk.downmods_cast,0) > 0
                then (coalesce(tk.upmods_cast,0)::numeric / (coalesce(tk.upmods_cast,0) + coalesce(tk.downmods_cast,0)))
            else null
        end as cast_upvote_ratio,
        case when tk.reputation >= 200000 then 'Legend'
             when tk.reputation >= 100000 then 'Elite'
             when tk.reputation >= 50000 then 'Expert'
             when tk.reputation >= 10000 then 'Pro'
             when tk.reputation >= 1000 then 'Enthusiast'
             else 'Rookie'
        end as user_tier
    from topk tk
    left join user_link_stats uls on uls.user_id = tk.user_id
    left join comment_stats cs on cs.user_id = tk.user_id
),
ranked_final as (
    select
        f.*,
        rank() over (order by
            coalesce(f.answers,0) desc,
            coalesce(f.accepted_rate_pct,0) desc,
            coalesce(f.questions,0) desc,
            coalesce(f.badge_count,0) desc,
            f.reputation desc,
            f.user_id
        ) as global_rank
    from final f
)
select
    rf.user_id,
    rf.displayname,
    rf.user_tier,
    rf.global_rank,
    rf.activity_rank,
    rf.top_tag,
    rf.reputation,
    rf.answers,
    rf.accepted_answers_count,
    rf.accepted_rate_pct,
    rf.questions,
    rf.questions_accept_pct,
    rf.total_views,
    rf.total_favs,
    rf.dup_links_user,
    rf.reg_links_user,
    rf.comments_made,
    rf.thanks_comments,
    rf.upmods_cast,
    rf.downmods_cast,
    rf.cast_upvote_ratio,
    rf.bounty_events,
    rf.bounty_amount_total,
    rf.posts_closed,
    rf.posts_reopened,
    rf.avg_answer_score,
    rf.avg_views_nonzero,
    rf.creationdate,
    rf.last_badge_date
from ranked_final rf
where
    (rf.top_tag is not null or rf.answers > 0 or rf.questions > 0)
    and coalesce(rf.accepted_rate_pct, 0) >= 0
    and not (rf.location ilike '%test%' and rf.reputation < 10)
order by rf.global_rank, rf.user_id
limit 250;