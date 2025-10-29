-- {"query": "538.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2808} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= now() - interval '3 years'
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        coalesce(sum(p.score) filter (where p.posttypeid in (1,2)), 0) as total_score,
        count(*) filter (where p.closeddate is not null) as closed_count,
        max(p.lastactivitydate) as last_activity,
        percentile_cont(0.5) within group (order by p.score) as median_post_score
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= now() - interval '3 years'
    group by p.owneruserid
),
top_tags as (
    select
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.owneruserid is not null
      and p.creationdate >= now() - interval '3 years'
),
tag_rank as (
    select
        tt.user_id,
        tt.tagname,
        count(*) as tag_uses,
        dense_rank() over (partition by tt.user_id order by count(*) desc, tt.tagname) as rnk
    from top_tags tt
    group by tt.user_id, tt.tagname
),
user_top3_tags as (
    select user_id,
           string_agg(tagname || ':' || tag_uses, ', ' order by rnk) as top3_tags
    from tag_rank
    where rnk <= 3
    group by user_id
),
vote_agg as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_rcvd,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_rcvd,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes_rcvd
    from posts p
    left join votes v
      on v.postid = p.id
     and v.creationdate >= now() - interval '3 years'
    where p.owneruserid is not null
      and p.creationdate >= now() - interval '3 years'
    group by p.owneruserid
),
comment_stats as (
    select
        p.owneruserid as user_id,
        count(c.id) as comments_on_posts,
        coalesce(sum(c.score), 0) as comment_score_sum,
        max(c.creationdate) as last_comment_date
    from posts p
    left join comments c
      on c.postid = p.id
     and c.creationdate >= now() - interval '3 years'
    where p.owneruserid is not null
      and p.creationdate >= now() - interval '3 years'
    group by p.owneruserid
),
badge_recent as (
    select
        b.userid as user_id,
        count(*) as badges_last_year,
        count(*) filter (where b.class = 1) as gold_last_year,
        count(*) filter (where b.class = 2) as silver_last_year,
        count(*) filter (where b.class = 3) as bronze_last_year,
        max(b.date) as last_badge_date
    from badges b
    where b.date >= now() - interval '1 year'
    group by b.userid
),
q_close_reasons as (
    select
        ph.postid,
        max(ph.creationdate) as last_close_date,
        max(ph.comment) filter (where ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$') as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid = 10
      and ph.creationdate >= now() - interval '3 years'
    group by ph.postid
),
dupe_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as dup_links_out,
        count(*) filter (where pl.linktypeid = 1) as links_out
    from postlinks pl
    where pl.creationdate >= now() - interval '3 years'
    group by pl.postid
),
answer_accepts as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers
    from posts q
    join posts a
      on a.id = q.acceptedanswerid
    where q.creationdate >= now() - interval '3 years'
      and a.owneruserid is not null
    group by a.owneruserid
),
question_quality as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1 and p.viewcount >= 1000) as q_1k_views,
        avg(nullif(p.viewcount,0)) filter (where p.posttypeid = 1) as avg_q_views,
        sum(case when p.posttypeid = 1 and p.favoritecount is not null and p.favoritecount >= 5 then 1 else 0 end) as q_fav_5plus
    from posts p
    where p.creationdate >= now() - interval '3 years'
      and p.owneruserid is not null
    group by p.owneruserid
),
user_recent_post as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.posttypeid,
        p.creationdate,
        row_number() over (partition by p.owneruserid order by p.creationdate desc, p.id desc) as rn
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= now() - interval '3 years'
),
user_recent_post_details as (
    select
        urp.user_id,
        urp.post_id,
        urp.posttypeid,
        urp.creationdate as recent_post_date,
        p.score as recent_post_score,
        p.viewcount as recent_post_views,
        coalesce(qcr.last_close_reason_id, '0') as recent_close_reason_id,
        coalesce(dl.dup_links_out, 0) as recent_dup_links_out
    from user_recent_post urp
    join posts p on p.id = urp.post_id
    left join q_close_reasons qcr on qcr.postid = p.id
    left join dupe_links dl on dl.postid = p.id
    where urp.rn = 1
),
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ua.q_count,
        ua.a_count,
        ua.total_score,
        ua.closed_count,
        ua.last_activity,
        ua.median_post_score,
        va.upvotes_rcvd,
        va.downvotes_rcvd,
        va.net_votes_rcvd,
        cs.comments_on_posts,
        cs.comment_score_sum,
        cs.last_comment_date,
        br.badges_last_year,
        br.gold_last_year,
        br.silver_last_year,
        br.bronze_last_year,
        br.last_badge_date,
        at.accepted_answers,
        qq.q_1k_views,
        qq.avg_q_views,
        qq.q_fav_5plus,
        urpd.post_id as recent_post_id,
        urpd.posttypeid as recent_post_type,
        urpd.recent_post_date,
        urpd.recent_post_score,
        urpd.recent_post_views,
        urpd.recent_close_reason_id,
        urpd.recent_dup_links_out,
        utt.top3_tags,
        ru.website_host,
        ru.location
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
    left join badge_recent br on br.user_id = ru.user_id
    left join answer_accepts at on at.user_id = ru.user_id
    left join question_quality qq on qq.user_id = ru.user_id
    left join user_recent_post_details urpd on urpd.user_id = ru.user_id
    left join user_top3_tags utt on utt.user_id = ru.user_id
),
scored as (
    select
        ur.*,
        -- Composite engagement score combining multiple signals
        round(
            coalesce(ln(1 + ua_coef.total_posts), 0)
          + 0.25 * coalesce(ur.net_votes_rcvd, 0)
          + 0.5 * coalesce(ur.accepted_answers, 0)
          + 0.1 * coalesce(ur.q_1k_views, 0)
          + 0.05 * coalesce(ur.badges_last_year, 0)
          + 0.01 * coalesce(ur.comment_score_sum, 0)
          + case when ur.recent_close_reason_id::int in (101,102,103,104,105) then -2 else 0 end
          + case when ur.recent_dup_links_out > 0 then -1 else 0 end
          + case when ur.recent_post_type = 2 and ur.recent_post_score >= 1 then 0.5 else 0 end
          , 3) as engagement_score
    from user_rollup ur
    left join (
        select user_id, sum(coalesce(q_count,0) + coalesce(a_count,0)) as total_posts
        from user_activity
        group by user_id
    ) ua_coef on ua_coef.user_id = ur.user_id
),
ranked as (
    select
        s.*,
        row_number() over (order by s.engagement_score desc, s.reputation desc, s.last_activity desc nulls last, s.user_id) as global_rank,
        row_number() over (partition by s.cohort_month order by s.engagement_score desc, s.reputation desc, s.user_id) as cohort_rank,
        ntile(10) over (order by s.engagement_score desc) as decile,
        avg(s.engagement_score) over () as avg_score_overall,
        avg(s.engagement_score) over (partition by s.cohort_month) as avg_score_by_cohort
    from scored s
),
nullable_demo as (
    select
        r.*,
        coalesce(nullif(trim(r.location), ''), 'Unknown') as norm_location,
        case
            when position(',' in coalesce(r.top3_tags, '')) > 0 then split_part(r.top3_tags, ',', 1)
            when coalesce(r.top3_tags, '') = '' then 'NoTags'
            else r.top3_tags
        end as first_tag_stat
    from ranked r
)
select
    nd.user_id,
    nd.displayname,
    nd.reputation,
    nd.cohort_month,
    nd.global_rank,
    nd.cohort_rank,
    nd.decile,
    nd.engagement_score,
    nd.avg_score_overall,
    nd.avg_score_by_cohort,
    nd.q_count,
    nd.a_count,
    nd.total_score,
    nd.upvotes_rcvd,
    nd.downvotes_rcvd,
    nd.net_votes_rcvd,
    nd.accepted_answers,
    nd.q_1k_views,
    nd.avg_q_views,
    nd.q_fav_5plus,
    nd.badges_last_year,
    nd.gold_last_year,
    nd.silver_last_year,
    nd.bronze_last_year,
    nd.last_badge_date,
    nd.comments_on_posts,
    nd.comment_score_sum,
    nd.last_comment_date,
    nd.recent_post_id,
    nd.recent_post_type,
    nd.recent_post_date,
    nd.recent_post_score,
    nd.recent_post_views,
    nd.recent_close_reason_id,
    nd.recent_dup_links_out,
    nd.top3_tags,
    nd.first_tag_stat,
    nd.website_host,
    nd.norm_location
from nullable_demo nd
where
    (nd.engagement_score > nd.avg_score_overall or nd.cohort_rank <= 10)
    and coalesce(nd.q_count, 0) + coalesce(nd.a_count, 0) > 0
    and not exists (
        select 1
        from posts p_bad
        where p_bad.owneruserid = nd.user_id
          and p_bad.creationdate >= now() - interval '90 days'
          and p_bad.score < -5
    )
order by nd.global_rank
limit 250;