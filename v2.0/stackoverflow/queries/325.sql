-- {"query": "325.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3315}
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.location,
           u.creationdate,
           u.upvotes,
           u.downvotes,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
           dense_rank() over (order by u.creationdate desc) as recency_rank
    from users u
),
heavy_commenters as (
    select c.userid,
           count(*) as comment_count,
           sum(case when c.score >= 5 then 1 else 0 end) as high_score_comments,
           max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
question_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as questions,
           count(*) filter (where p.posttypeid = 2) as answers,
           sum(coalesce(p.score,0)) as total_post_score,
           sum(coalesce(p.viewcount,0)) as total_views,
           avg(nullif(p.answercount,0)) filter (where p.posttypeid = 1) as avg_answers_per_q_nonzero,
           max(p.creationdate) as last_post_date,
           min(p.creationdate) as first_post_date
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
accepted_answerers as (
    select a.owneruserid as user_id,
           count(*) as accepted_answers
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
tag_expertise as (
    -- Split tags using standard SQL functions: remove leading/trailing <> then split by '><'
    -- Use a derived table to unnest tags for portability
    select t.user_id,
           lower(trim(' ' from t.tagname)) as tagname,
           count(*) as tag_posts,
           sum(coalesce(p.score,0)) as tag_score
    from posts p
    cross join lateral (
        select trim(' ' from s) as tagname,
               p.owneruserid as user_id
        from (
            -- replace substring(p.tags,2,length(p.tags)-2) -> remove first and last char
            select regexp_split_to_table(
                     case when p.tags like '<%>' then substring(p.tags from 2 for char_length(p.tags)-2) else p.tags end,
                     '><'
                   ) as s
        ) st
    ) t
    where p.posttypeid = 1
      and p.tags is not null
      and p.owneruserid is not null
    group by t.user_id, lower(trim(' ' from t.tagname))
),
top_tag_per_user as (
    select user_id,
           tagname,
           tag_posts,
           tag_score,
           row_number() over (partition by user_id order by tag_posts desc, tag_score desc, tagname) as rn
    from tag_expertise
),
duplicate_closures as (
    select ph.userid,
           count(*) as duplicate_closes,
           sum(case when (ph.comment ~ '^[0-9]+$') then 1 else 0 end) as structured_reason_refs
    from posthistory ph
    where ph.posthistorytypeid in (10,35)
      and (ph.comment is not null)
      and exists (
          select 1
          from closereasontypes crt
          where (ph.comment ~ '^[0-9]+$' and cast(crt.id as text) = ph.comment)
             or (ph.text ilike '%' || crt.name || '%')
      )
    group by ph.userid
),
bounty_earners as (
    select v.userid as user_id,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_earned,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_offered,
           count(*) filter (where v.votetypeid in (8,9)) as bounty_events
    from votes v
    where v.userid is not null
    group by v.userid
),
link_graph as (
    select pl.postid,
           pl.relatedpostid,
           pl.linktypeid,
           case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
),
user_link_stats as (
    select p.owneruserid as user_id,
           count(*) filter (where lg.is_duplicate = 1) as duplicate_links,
           count(*) filter (where lg.linktypeid = 1) as linked_refs
    from posts p
    left join link_graph lg
      on lg.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
post_type_names as (
    select id, name from posttypes
),
vote_type_names as (
    select id, name from votetypes
),
user_badges as (
    select b.userid as user_id,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold,
           sum(case when b.class = 2 then 1 else 0 end) as silver,
           sum(case when b.class = 3 then 1 else 0 end) as bronze,
           sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
activity_by_month as (
    select p.owneruserid as user_id,
           date_trunc('month', p.creationdate) as month,
           count(*) as posts_in_month,
           sum(coalesce(p.score,0)) as score_in_month
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
recent_trend as (
    select abm.user_id,
           avg(score_in_month) filter (where month >= (timestamp '2024-10-01 12:34:56' - interval '6 months')) as avg_score_recent,
           avg(score_in_month) filter (where month < (timestamp '2024-10-01 12:34:56' - interval '6 months') and month >= (timestamp '2024-10-01 12:34:56' - interval '12 months')) as avg_score_prev
    from activity_by_month abm
    group by abm.user_id
),
user_core as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.location,
           ru.creationdate,
           ru.websiteurl_norm,
           qa.questions,
           qa.answers,
           qa.total_post_score,
           qa.total_views,
           qa.avg_answers_per_q_nonzero,
           qa.last_post_date,
           qa.first_post_date,
           aa.accepted_answers,
           hb.comment_count,
           hb.high_score_comments,
           hb.last_comment_date,
           ub.total_badges,
           ub.gold, ub.silver, ub.bronze, ub.tag_badges, ub.last_badge_date,
           coalesce(be.bounty_earned,0) as bounty_earned,
           coalesce(be.bounty_offered,0) as bounty_offered,
           coalesce(be.bounty_events,0) as bounty_events,
           coalesce(uls.duplicate_links,0) as duplicate_links,
           coalesce(uls.linked_refs,0) as linked_refs,
           coalesce(dc.duplicate_closes,0) as duplicate_closes,
           coalesce(dc.structured_reason_refs,0) as structured_reason_refs,
           rt.avg_score_recent,
           rt.avg_score_prev
    from recent_users ru
    left join question_activity qa on qa.user_id = ru.user_id
    left join accepted_answerers aa on aa.user_id = ru.user_id
    left join heavy_commenters hb on hb.userid = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join bounty_earners be on be.user_id = ru.user_id
    left join user_link_stats uls on uls.user_id = ru.user_id
    left join duplicate_closures dc on dc.userid = ru.user_id
    left join recent_trend rt on rt.user_id = ru.user_id
    where ru.recency_rank <= 5000
),
normalized as (
    select uc.user_id,
           uc.displayname,
           uc.reputation,
           uc.location,
           uc.creationdate,
           uc.websiteurl_norm,
           uc.questions,
           uc.answers,
           uc.total_post_score,
           uc.total_views,
           uc.avg_answers_per_q_nonzero,
           uc.last_post_date,
           uc.first_post_date,
           uc.accepted_answers,
           uc.comment_count,
           uc.high_score_comments,
           uc.last_comment_date,
           uc.total_badges,
           uc.gold,
           uc.silver,
           uc.bronze,
           uc.tag_badges,
           uc.last_badge_date,
           uc.bounty_earned,
           uc.bounty_offered,
           uc.bounty_events,
           uc.duplicate_links,
           uc.linked_refs,
           uc.duplicate_closes,
           uc.structured_reason_refs,
           uc.avg_score_recent,
           uc.avg_score_prev,
           nullif(uc.answers,0) as answers_nonzero,
           nullif(uc.questions,0) as questions_nonzero,
           case when coalesce(uc.answers,0) + coalesce(uc.questions,0) > 0
                then cast(uc.total_post_score as numeric) / (coalesce(uc.answers,0) + coalesce(uc.questions,0))
                else null end as avg_score_per_post,
           case when uc.total_views > 0 then cast(uc.total_post_score as numeric) / uc.total_views else null end as score_per_view,
           case when uc.answers is not null and uc.answers > 0 then cast(uc.accepted_answers as numeric) / nullif(uc.answers,0) else null end as accept_rate,
           case when uc.bounty_offered > 0 then cast(uc.bounty_earned as numeric) / uc.bounty_offered else null end as bounty_roi,
           case when uc.avg_score_prev is null and uc.avg_score_recent is not null then 1
                when uc.avg_score_prev is not null and uc.avg_score_recent is null then -1
                when uc.avg_score_prev is null and uc.avg_score_recent is null then 0
                when uc.avg_score_prev = 0 and uc.avg_score_recent <> 0 then 1
                when uc.avg_score_prev <> 0 then (uc.avg_score_recent - uc.avg_score_prev) / nullif(uc.avg_score_prev,0)
                else 0 end as score_trend_ratio
    from user_core uc
),
top_tag as (
    select t.user_id,
           t.tagname as top_tag,
           t.tag_posts,
           t.tag_score
    from top_tag_per_user t
    where t.rn = 1
),
post_mix as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           count(*) filter (where p.posttypeid not in (1,2) or p.posttypeid is null) as other_count,
           count(distinct p.posttypeid) as distinct_types
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
rankings as (
    select n.user_id,
           row_number() over (order by coalesce(n.reputation,0) desc, coalesce(n.total_post_score,0) desc) as rep_rank,
           row_number() over (order by coalesce(n.avg_score_per_post, -1) desc) as avg_post_score_rank,
           row_number() over (order by coalesce(n.accept_rate, -1) desc) as accept_rate_rank,
           row_number() over (order by coalesce(n.score_trend_ratio, -2) desc) as trend_rank,
           row_number() over (order by coalesce(n.bounty_earned,0) desc) as bounty_rank
    from normalized n
),
final_scores as (
    select n.user_id,
           n.displayname,
           n.location,
           n.websiteurl_norm,
           n.reputation,
           n.questions,
           n.answers,
           n.accepted_answers,
           n.total_post_score,
           n.total_views,
           n.avg_score_per_post,
           n.accept_rate,
           n.bounty_earned,
           n.bounty_offered,
           n.bounty_roi,
           n.score_trend_ratio,
           coalesce(tt.top_tag, '(none)') as top_tag,
           coalesce(tt.tag_posts,0) as top_tag_posts,
           coalesce(tt.tag_score,0) as top_tag_score,
           pm.q_count, pm.a_count, pm.other_count, pm.distinct_types,
           r.rep_rank, r.avg_post_score_rank, r.accept_rate_rank, r.trend_rank, r.bounty_rank,
           (
             (1000.0 / nullif(r.rep_rank,0)) * 0.30 +
             (1000.0 / nullif(r.avg_post_score_rank,0)) * 0.20 +
             (1000.0 / nullif(r.accept_rate_rank,0)) * 0.15 +
             (1000.0 / nullif(r.trend_rank,0)) * 0.20 +
             (1000.0 / nullif(r.bounty_rank,0)) * 0.15 +
             least(coalesce(tt.tag_posts,0), 100) * 0.05
           ) as composite_score
    from normalized n
    left join top_tag tt on tt.user_id = n.user_id
    left join post_mix pm on pm.user_id = n.user_id
    join rankings r on r.user_id = n.user_id
),
dedup_display as (
    select fs.*,
           case
             when fs.displayname is null or fs.displayname ~ '^\s*$' then '(anonymous)'
             when char_length(fs.displayname) > 40 then substring(fs.displayname from 1 for 37) || '...'
             else fs.displayname
           end as displayname_norm,
           case
             when fs.location is null or trim(fs.location) = '' then '(unknown)'
             when position(',' in fs.location) > 0 then split_part(fs.location, ',', 1)
             else fs.location
           end as location_norm
    from final_scores fs
),
with_null_logic as (
    select dd.*,
           coalesce(nullif(dd.top_tag, '(none)'), '(none)') as top_tag_norm,
           case when dd.accept_rate is null then -1 else dd.accept_rate end as accept_rate_for_sort,
           case when dd.avg_score_per_post is null then -999.0 else dd.avg_score_per_post end as avg_score_for_sort
    from dedup_display dd
)
select
    w.user_id,
    w.displayname_norm as display_name,
    w.location_norm as location,
    w.websiteurl_norm as website,
    w.reputation,
    w.questions,
    w.answers,
    w.accepted_answers,
    w.total_post_score,
    w.total_views,
    round(w.avg_score_per_post::numeric, 3) as avg_score_per_post,
    round(w.accept_rate::numeric, 3) as accept_rate,
    w.top_tag_norm as top_tag,
    w.top_tag_posts,
    w.top_tag_score,
    w.q_count, w.a_count, w.other_count, w.distinct_types,
    w.bounty_earned, w.bounty_offered, round(w.bounty_roi::numeric,3) as bounty_roi,
    round(w.score_trend_ratio::numeric,3) as score_trend_ratio,
    w.rep_rank, w.avg_post_score_rank, w.accept_rate_rank, w.trend_rank, w.bounty_rank,
    round(w.composite_score::numeric, 3) as composite_score
from with_null_logic w
where (
        w.answers is not null and w.answers >= 1
      )
  and (
        w.top_tag_norm is not null
        and w.top_tag_posts >= 0
      )
  and not exists (
        select 1
        from posts p2
        where p2.owneruserid = w.user_id
          and p2.posttypeid = 1
          and p2.closeddate is not null
          and p2.score < 0
          and p2.creationdate > timestamp '2024-10-01 12:34:56' - interval '365 days'
      )
order by w.composite_score desc, w.reputation desc, w.user_id
limit 200;