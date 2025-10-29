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
        dense_rank() over (order by u.creationdate desc) as recency_rank
    from users u
),
user_badge_agg as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
q_and_a as (
    select
        p.owneruserid as user_id,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as questions,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as answers,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
        sum(coalesce(p.answercount,0)) as total_answercount_for_questions
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
post_quality as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.score,
        p.viewcount,
        p.creationdate,
        p.tags,
        p.title,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        row_number() over (partition by p.owneruserid order by p.score desc nulls last, p.viewcount desc nulls last, p.creationdate desc) as rn_best_by_user
    from posts p
    left join votes v on v.postid = p.id
    where p.posttypeid in (1,2)
    group by p.id, p.owneruserid, p.posttypeid, p.score, p.viewcount, p.creationdate, p.tags, p.title
),
best_posts as (
    select pq.*
    from post_quality pq
    where pq.rn_best_by_user = 1
),
tag_extraction as (
    select
        p.id as post_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and length(p.tags) > 2
),
user_comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
        avg(nullif(length(c.text),0)) as avg_comment_length
    from comments c
    group by c.userid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_votes_count
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as dup_count
    from postlinks pl
    group by pl.postid
),
user_activity_window as (
    select
        p.owneruserid as user_id,
        cast(p.creationdate as date) as post_day,
        count(*) as posts_in_day,
        sum(coalesce(p.score,0)) as score_in_day
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid, cast(p.creationdate as date)
),
user_activity_rollup as (
    select
        uaw.user_id,
        sum(uaw.posts_in_day) as total_posts_days_window,
        avg(uaw.posts_in_day) as avg_posts_per_active_day,
        max(uaw.score_in_day) as max_daily_score,
        stddev_pop(uaw.score_in_day) as score_day_stddev
    from user_activity_window uaw
    group by uaw.user_id
),
accepted_answer_rates as (
    select
        q.owneruserid as user_id,
        count(*) filter (where q.acceptedanswerid is not null) as accepted_questions,
        count(*) filter (where q.acceptedanswerid is null) as unaccepted_questions,
        count(*) as total_questions
    from posts q
    where q.posttypeid = 1 and q.owneruserid is not null
    group by q.owneruserid
),
answer_accepts as (
    select
        a.owneruserid as user_id,
        count(*) as answers_posted,
        count(*) filter (where a.id = q.acceptedanswerid) as answers_accepted
    from posts a
    left join posts q on q.id = a.parentid and q.posttypeid = 1
    where a.posttypeid = 2 and a.owneruserid is not null
    group by a.owneruserid
),
user_vote_ratio as (
    select
        u.id as user_id,
        nullif(u.upvotes,0) * 1.0 / nullif(nullif(u.downvotes,0),0) as up_to_down_vote_ratio_unsafe,
        case
            when coalesce(u.downvotes,0) = 0 and coalesce(u.upvotes,0) = 0 then null
            when coalesce(u.downvotes,0) = 0 then cast(u.upvotes as numeric)
            else cast(u.upvotes as numeric) / nullif(cast(u.downvotes as numeric),0)
        end as up_to_down_vote_ratio
    from users u
),
tag_popularity as (
    select
        te.tag,
        count(distinct te.post_id) as posts_with_tag,
        sum(p.score) as tag_total_score,
        avg(p.viewcount) as tag_avg_views
    from tag_extraction te
    join posts p on p.id = te.post_id
    group by te.tag
),
user_top_tag as (
    select
        te_owner.user_id,
        te_owner.tag,
        rank() over (partition by te_owner.user_id order by count(*) desc, sum(p.score) desc nulls last) as rnk
    from (
        select p.owneruserid as user_id, te.tag
        from posts p
        join tag_extraction te on te.post_id = p.id
        where p.posttypeid = 1 and p.owneruserid is not null
    ) te_owner
    join posts p on p.owneruserid = te_owner.user_id and p.posttypeid = 1
    join tag_extraction te2 on te2.post_id = p.id and te2.tag = te_owner.tag
    group by te_owner.user_id, te_owner.tag
),
user_top_tag_pick as (
    select user_id, tag as top_tag
    from user_top_tag
    where rnk = 1
),
user_post_type_mix as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_cnt,
        count(*) filter (where p.posttypeid = 2) as a_cnt,
        count(*) as total_pa_cnt
    from posts p
    where p.posttypeid in (1,2) and p.owneruserid is not null
    group by p.owneruserid
),
user_null_safety as (
    select
        u.id as user_id,
        coalesce(nullif(trim(u.displayname),''), '(anonymous)') as safe_displayname,
        nullif(trim(u.location),'') as normalized_location,
        case
            when u.websiteurl is null or trim(u.websiteurl) = '' then null
            when position('http' in lower(u.websiteurl)) = 1 then u.websiteurl
            else 'http://' || u.websiteurl
        end as normalized_website
    from users u
),
recent_hot_bumps as (
    select
        ph.postid,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (50,52)) as last_hot_or_bump
    from posthistory ph
    where ph.posthistorytypeid in (50,52,53)
    group by ph.postid
),
ranked_users as (
    select
        ru.user_id,
        row_number() over (
            order by
                coalesce(qa.total_post_score,0) desc,
                coalesce(qa.answers,0) desc,
                coalesce(qa.questions,0) desc,
                ru.reputation desc
        ) as overall_rank
    from recent_users ru
    left join q_and_a qa on qa.user_id = ru.user_id
),
final_user as (
    select
        ru.user_id,
        un.safe_displayname as displayname,
        coalesce(ru.location, un.normalized_location) as location,
        un.normalized_website as website,
        ru.reputation,
        ru.creationdate,
        ru.views,
        ru.upvotes,
        ru.downvotes,
        qa.questions,
        qa.answers,
        qa.total_post_score,
        qa.question_views,
        qa.total_answercount_for_questions,
        uba.total_badges,
        uba.gold_badges,
        uba.silver_badges,
        uba.bronze_badges,
        uba.first_badge_date,
        uba.last_badge_date,
        ucs.comment_count,
        ucs.positive_comments,
        ucs.avg_comment_length,
        uar.total_questions,
        uar.accepted_questions,
        uar.unaccepted_questions,
        aa.answers_posted,
        aa.answers_accepted,
        uvr.up_to_down_vote_ratio,
        uarm.total_posts_days_window,
        uarm.avg_posts_per_active_day,
        uarm.max_daily_score,
        uarm.score_day_stddev,
        utp.top_tag,
        upm.q_cnt,
        upm.a_cnt,
        upm.total_pa_cnt,
        rp.post_id as best_post_id,
        rp.posttypeid as best_post_type,
        rp.score as best_post_score,
        rp.viewcount as best_post_views,
        rp.title as best_post_title,
        rp.tags as best_post_tags,
        ce.first_close_date,
        ce.close_votes_count,
        dl.dup_count,
        rhb.last_hot_or_bump,
        ru.recency_rank,
        ru.displayname as raw_displayname,
        ru.location as raw_location,
        ru.user_id as ru_user_id,
        coalesce(qa.total_post_score,0) as qa_total_post_score,
        coalesce(qa.answers,0) as qa_answers,
        coalesce(qa.questions,0) as qa_questions,
        ru.reputation as ru_reputation,
        ru.creationdate as ru_creationdate,
        ru.views as ru_views,
        ru.upvotes as ru_upvotes,
        ru.downvotes as ru_downvotes,
        ru.displayname as ru_displayname,
        rnk.overall_rank
    from recent_users ru
    left join user_null_safety un on un.user_id = ru.user_id
    left join q_and_a qa on qa.user_id = ru.user_id
    left join user_badge_agg uba on uba.userid = ru.user_id
    left join user_comment_stats ucs on ucs.user_id = ru.user_id
    left join accepted_answer_rates uar on uar.user_id = ru.user_id
    left join answer_accepts aa on aa.user_id = ru.user_id
    left join user_vote_ratio uvr on uvr.user_id = ru.user_id
    left join user_activity_rollup uarm on uarm.user_id = ru.user_id
    left join user_top_tag_pick utp on utp.user_id = ru.user_id
    left join user_post_type_mix upm on upm.user_id = ru.user_id
    left join best_posts rp on rp.user_id = ru.user_id
    left join close_events ce on ce.postid = rp.post_id
    left join dup_links dl on dl.postid = rp.post_id
    left join recent_hot_bumps rhb on rhb.postid = rp.post_id
    left join ranked_users rnk on rnk.user_id = ru.user_id
),
outliers as (
    select
        fu.user_id,
        case when fu.total_post_score is null then 0 else 1 end as has_posts,
        case when fu.answers_posted > 0 and cast(fu.answers_accepted as numeric) / cast(fu.answers_posted as numeric) > 0.8 then 1 else 0 end as high_accept_rate_flag,
        case when fu.up_to_down_vote_ratio is not null and fu.up_to_down_vote_ratio > 10 then 1 else 0 end as vote_ratio_outlier,
        case when fu.avg_posts_per_active_day is not null and fu.avg_posts_per_active_day > 5 then 1 else 0 end as posting_spike
    from final_user fu
),
normalized_scores as (
    select
        fu.*,
        (select avg(x.total_post_score) from (
            select coalesce(total_post_score,0) as total_post_score,
                   row_number() over (order by coalesce(total_post_score,0)) as rn,
                   count(*) over () as cnt
            from final_user
        ) x where x.rn in ((x.cnt+1)/2, (x.cnt+2)/2)) as med_total_post_score,
        (select avg(x.question_views) from (
            select coalesce(question_views,0) as question_views,
                   row_number() over (order by coalesce(question_views,0)) as rn,
                   count(*) over () as cnt
            from final_user
        ) x where x.rn in (cast(floor(0.9 * x.cnt) as integer), cast(ceil(0.9 * x.cnt) as integer))) as p90_question_views,
        avg(coalesce(fu.answers,0)) over () as avg_answers_global,
        stddev_pop(coalesce(fu.answers,0)) over () as std_answers_global
    from final_user fu
),
scored as (
    select
        ns.*,
        case
            when ns.med_total_post_score is null or ns.med_total_post_score = 0 then null
            else cast(coalesce(ns.total_post_score,0) as numeric) / nullif(cast(ns.med_total_post_score as numeric),0)
        end as score_vs_median,
        case
            when ns.std_answers_global is null or ns.std_answers_global = 0 then null
            else (coalesce(ns.answers,0) - ns.avg_answers_global) / nullif(ns.std_answers_global,0)
        end as answers_zscore,
        case
            when ns.p90_question_views is null or ns.p90_question_views = 0 then null
            else least(1.0, cast(coalesce(ns.question_views,0) as numeric) / nullif(cast(ns.p90_question_views as numeric),0))
        end as question_views_norm
    from normalized_scores ns
),
topn as (
    select
        s.*,
        row_number() over (
            order by
                coalesce(s.score_vs_median,0) desc,
                coalesce(s.answers_zscore,0) desc,
                coalesce(s.question_views_norm,0) desc,
                s.reputation desc,
                s.overall_rank
        ) as perf_rank
    from scored s
)
select
    t.perf_rank,
    t.user_id,
    coalesce(t.displayname, '(anonymous)') as displayname,
    coalesce(nullif(t.location,''), 'Unknown') as location,
    t.reputation,
    t.questions,
    t.answers,
    t.total_post_score,
    t.question_views,
    t.total_answercount_for_questions,
    t.total_badges,
    t.gold_badges,
    t.silver_badges,
    t.bronze_badges,
    t.comment_count,
    t.positive_comments,
    round(cast(t.avg_comment_length as numeric),2) as avg_comment_length,
    t.total_questions,
    t.accepted_questions,
    t.unaccepted_questions,
    t.answers_posted,
    t.answers_accepted,
    round(cast(t.up_to_down_vote_ratio as numeric),2) as up_to_down_vote_ratio,
    t.total_posts_days_window,
    round(cast(t.avg_posts_per_active_day as numeric),2) as avg_posts_per_active_day,
    t.max_daily_score,
    round(cast(t.score_day_stddev as numeric),2) as score_day_stddev,
    t.top_tag,
    t.q_cnt,
    t.a_cnt,
    t.total_pa_cnt,
    t.best_post_id,
    t.best_post_type,
    t.best_post_score,
    t.best_post_views,
    left(coalesce(t.best_post_title,''), 120) as best_post_title_snippet,
    case when t.best_post_tags is null then '[]' else t.best_post_tags end as best_post_tags_raw,
    t.first_close_date,
    t.close_votes_count,
    t.dup_count,
    t.last_hot_or_bump,
    round(coalesce(t.score_vs_median,0)::numeric,3) as score_vs_median,
    round(coalesce(t.answers_zscore,0)::numeric,3) as answers_zscore,
    round(coalesce(t.question_views_norm,0)::numeric,3) as question_views_norm
from topn t
where
    (
        t.best_post_score is not null
        or (t.questions is not null and t.answers is not null)
    )
    and (
        t.top_tag is null
        or exists (
            select 1
            from tag_popularity tp
            where tp.tag = t.top_tag
              and tp.posts_with_tag > 0
              and (tp.tag_total_score > 0 or tp.tag_avg_views > 0)
        )
    )
order by t.perf_rank
limit 200;