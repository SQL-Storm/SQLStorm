-- {"query": "826.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3481} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_global
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as post_score_sum,
        sum(coalesce(p.viewcount,0)) as post_views_sum,
        avg(nullif(p.answercount,0)) filter (where p.posttypeid = 1) as avg_answers_per_q_nonzero,
        max(p.creationdate) as last_post_at,
        min(p.creationdate) as first_post_at
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select min(creationdate) from recent_users)
    group by p.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score_sum,
        max(c.creationdate) as last_comment_at
    from comments c
    where c.userid is not null
      and c.creationdate >= (select min(creationdate) from recent_users)
    group by c.userid
),
badge_activity as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_at
    from badges b
    where b.date >= (select min(creationdate) from recent_users)
    group by b.userid
),
vote_activity as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 10) as deletions_cast,
        max(v.creationdate) as last_vote_at
    from votes v
    where v.userid is not null
      and v.creationdate >= (select min(creationdate) from recent_users)
    group by v.userid
),
qa_quality as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as questions_with_accepted,
        count(*) filter (where p.posttypeid = 2 and exists (
            select 1
            from posts q
            where q.id = p.parentid
              and q.acceptedanswerid = p.id
        )) as answers_accepted,
        percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_post_score
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
question_tag_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as tagged_qs,
        count(*) filter (
            where p.tags is not null
              and exists (
                  select 1
                  from unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) t(tag)
                  where lower(t.tag) in ('sql','postgresql','mysql','tsql','oracle','sqlite')
              )
        ) as tagged_sql_family_qs
    from posts p
    where p.posttypeid = 1
      and p.owneruserid is not null
    group by p.owneruserid
),
post_closure_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_at,
        max(ph.creationdate) as last_close_at,
        count(*) as close_events,
        count(*) filter (where ph.comment in ('101','102','103','104','105','1','2','3','4','7','10','20')) as close_with_reason_events
    from posthistory ph
    where ph.posthistorytypeid in (10,35) -- closed or migrated away
    group by ph.postid
),
user_close_profile as (
    select
        p.owneruserid as user_id,
        count(*) as closed_posts,
        sum(coalesce(p.score,0)) as closed_posts_score_sum,
        count(*) filter (where p.closeddate is not null) as closed_flagged,
        max(pce.last_close_at) as last_close_event_at
    from posts p
    left join post_closure_events pce on pce.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
dupe_graph as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.creationdate,
        pl.linktypeid
    from postlinks pl
    where pl.linktypeid = 3
),
user_dupe_metrics as (
    select
        coalesce(p.owneruserid, rp.owneruserid) as user_id,
        count(*) as dup_links_involving_user,
        count(distinct case when p.posttypeid = 1 then p.id when rp.posttypeid = 1 then rp.id end) as distinct_questions_involved
    from dupe_graph d
    left join posts p on p.id = d.postid
    left join posts rp on rp.id = d.relatedpostid
    group by coalesce(p.owneruserid, rp.owneruserid)
),
activity_calendar as (
    select
        u.id as user_id,
        d::date as activity_date,
        coalesce(pa.posts_on_day,0) as posts_on_day,
        coalesce(ca.comments_on_day,0) as comments_on_day
    from users u
    cross join lateral generate_series(date_trunc('month', (select min(creationdate) from recent_users))::date, current_date, interval '1 day') d
    left join lateral (
        select count(*) as posts_on_day
        from posts p
        where p.owneruserid = u.id
          and p.creationdate::date = d::date
    ) pa on true
    left join lateral (
        select count(*) as comments_on_day
        from comments c
        where c.userid = u.id
          and c.creationdate::date = d::date
    ) ca on true
),
calendar_rollup as (
    select
        user_id,
        sum(case when extract(dow from activity_date) in (1,2,3,4,5) then posts_on_day else 0 end) as wk_posts,
        sum(case when extract(dow from activity_date) in (0,6) then posts_on_day else 0 end) as we_posts,
        sum(comments_on_day) as total_comments_period
    from activity_calendar
    group by user_id
),
user_titles as (
    select
        p.owneruserid as user_id,
        avg(length(coalesce(p.title,''))) filter (where p.posttypeid = 1) as avg_title_len,
        max(length(coalesce(p.title,''))) filter (where p.posttypeid = 1) as max_title_len,
        min(nullif(length(coalesce(p.title,'')),0)) filter (where p.posttypeid = 1) as min_nonzero_title_len
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
top_answers as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.score,
        row_number() over (partition by p.owneruserid order by p.score desc nulls last, p.id) as rn
    from posts p
    where p.posttypeid = 2
      and p.owneruserid is not null
),
top_answer_stats as (
    select
        ta.user_id,
        avg(ta.score) filter (where ta.rn <= 3) as avg_top3_answer_score,
        sum(case when ta.rn <= 3 then 1 else 0 end) as top3_answers_count
    from top_answers ta
    group by ta.user_id
),
norms as (
    select
        avg(reputation::numeric) as avg_rep,
        stddev_pop(reputation::numeric) as sd_rep,
        avg(coalesce(ua.q_count,0)::numeric) as avg_q,
        stddev_pop(coalesce(ua.q_count,0)::numeric) as sd_q
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
),
user_ranked as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        coalesce(ua.post_score_sum,0) as post_score_sum,
        coalesce(ua.post_views_sum,0) as post_views_sum,
        ca.comment_count,
        ba.badge_count,
        qa.answers_accepted,
        qt.tagged_sql_family_qs,
        uc.closed_posts,
        ud.dup_links_involving_user,
        cr.wk_posts,
        cr.we_posts,
        ut.avg_title_len,
        tas.avg_top3_answer_score,
        greatest(
            coalesce(ua.last_post_at, timestamp 'epoch'),
            coalesce(ca.last_comment_at, timestamp 'epoch'),
            coalesce(ba.last_badge_at, timestamp 'epoch'),
            coalesce(va.last_vote_at, timestamp 'epoch')
        ) as last_seen_activity,
        case
            when position('http' in lower(coalesce(ru.websiteurl,''))) = 1 then 'has_url'
            when ru.websiteurl is null or ru.websiteurl = 'unknown' then 'no_url'
            else 'other_url'
        end as website_class,
        case when ru.location ilike '%remote%' then 1 else 0 end as loc_remote_flag,
        case when ru.reputation > 0 then ln(ru.reputation::numeric) else null end as rep_ln,
        (select count(*) from posts p2 where p2.owneruserid = ru.user_id and p2.posttypeid = 2 and p2.score > 0) as pos_answer_count,
        (select count(*) from comments c2 where c2.userid = ru.user_id and c2.score < 0) as neg_comment_count
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join badge_activity ba on ba.user_id = ru.user_id
    left join vote_activity va on va.user_id = ru.user_id
    left join qa_quality qa on qa.user_id = ru.user_id
    left join question_tag_metrics qt on qt.user_id = ru.user_id
    left join user_close_profile uc on uc.user_id = ru.user_id
    left join user_dupe_metrics ud on ud.user_id = ru.user_id
    left join calendar_rollup cr on cr.user_id = ru.user_id
    left join user_titles ut on ut.user_id = ru.user_id
    left join top_answer_stats tas on tas.user_id = ru.user_id
),
scored as (
    select
        ur.*,
        -- composite engagement score with null-safe arithmetic
        coalesce(ur.q_count,0)*1.0
        + coalesce(ur.a_count,0)*2.0
        + coalesce(ur.comment_count,0)*0.25
        + coalesce(ur.badge_count,0)*0.5
        + coalesce(ur.answers_accepted,0)*3.0
        + coalesce(ur.tagged_sql_family_qs,0)*1.5
        + coalesce(ur.closed_posts,0)*(-1.0)
        + coalesce(ur.dup_links_involving_user,0)*(-0.5)
        + coalesce(ur.wk_posts,0)*0.2
        + coalesce(ur.we_posts,0)*0.3
        + coalesce(ur.avg_top3_answer_score,0)*1.0
        + coalesce(ur.post_score_sum,0)*0.1
        as engagement_score,
        -- quality ratio guarded against zero/NULL
        case
            when coalesce(ur.q_count,0) + coalesce(ur.a_count,0) = 0 then null
            else (coalesce(ur.post_score_sum,0)::numeric) / nullif((coalesce(ur.q_count,0) + coalesce(ur.a_count,0))::numeric, 0)
        end as avg_score_per_post,
        -- recency decay
        exp(-extract(epoch from (now() - coalesce(ur.last_seen_activity, now()))) / 86400.0 / 30.0) as recency_weight
    from user_ranked ur
),
normalized as (
    select
        s.*,
        case
            when n.sd_rep is null or n.sd_rep = 0 then null
            else (s.reputation - n.avg_rep) / n.sd_rep
        end as z_rep,
        case
            when n.sd_q is null or n.sd_q = 0 then null
            else (s.q_count - n.avg_q) / n.sd_q
        end as z_q
    from scored s
    cross join norms n
),
final_rank as (
    select
        *,
        -- final score blending engagement, quality and recency
        (coalesce(engagement_score,0)::numeric * coalesce(recency_weight,1.0))
        + coalesce(avg_score_per_post,0)::numeric
        + coalesce(z_rep,0)::numeric
        + coalesce(z_q,0)::numeric
        + case when loc_remote_flag = 1 then 0.25 else 0 end
        as final_score,
        row_number() over (
            partition by cohort_month
            order by
                ((coalesce(engagement_score,0)::numeric * coalesce(recency_weight,1.0))
                 + coalesce(avg_score_per_post,0)::numeric
                 + coalesce(z_rep,0)::numeric
                 + coalesce(z_q,0)::numeric
                 + case when loc_remote_flag = 1 then 0.25 else 0 end) desc,
                user_id
        ) as cohort_rank
    from normalized
)
select
    fr.cohort_month,
    fr.cohort_rank,
    fr.user_id,
    coalesce(nullif(fr.displayname,''), concat('user#', fr.user_id::varchar)) as displayname,
    fr.reputation,
    round(fr.final_score::numeric, 3) as final_score,
    fr.engagement_score,
    round(coalesce(fr.avg_score_per_post,0)::numeric, 3) as avg_score_per_post,
    round(fr.recency_weight::numeric, 3) as recency_weight,
    fr.q_count,
    fr.a_count,
    fr.comment_count,
    fr.badge_count,
    fr.answers_accepted,
    fr.tagged_sql_family_qs,
    fr.closed_posts,
    fr.dup_links_involving_user,
    fr.wk_posts,
    fr.we_posts,
    round(coalesce(fr.avg_title_len,0)::numeric, 1) as avg_title_len,
    round(coalesce(fr.avg_top3_answer_score,0)::numeric,1) as avg_top3_answer_score,
    fr.last_seen_activity,
    fr.website_class
from final_rank fr
where fr.cohort_rank <= 50
   or fr.final_score >= (
        select percentile_cont(0.95) within group (order by final_score)
        from final_rank
    )
order by fr.cohort_month desc, fr.cohort_rank asc, fr.final_score desc;