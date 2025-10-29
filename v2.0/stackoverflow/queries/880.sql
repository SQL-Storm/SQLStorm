-- {"query": "880.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3046}
with recent_posts as (
  select p.id,
         p.posttypeid,
         p.creationdate,
         p.owneruserid,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.parentid
  from posts p
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_activity as (
  select u.id as userid,
         u.displayname,
         u.reputation,
         u.creationdate as usercreationdate,
         coalesce(u.location, 'Unknown') as location,
         count(distinct p.id) filter (where p.owneruserid = u.id) as post_count,
         count(distinct c.id) filter (where c.userid = u.id) as comment_count,
         count(*) filter (where v.votetypeid = 2) as upvotes_cast,
         count(*) filter (where v.votetypeid = 3) as downvotes_cast,
         sum(case when v.votetypeid in (2,3) then 1 else 0 end) as total_votes_cast,
         max(coalesce(p.lastactivitydate, p.creationdate)) as last_post_activity
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join votes v on v.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location
),
question_metrics as (
  select p.id as question_id,
         p.owneruserid as asker_id,
         p.score as q_score,
         p.viewcount as q_views,
         p.creationdate as q_created,
         p.acceptedanswerid,
         count(*) filter (where a.posttypeid = 2) as answer_count,
         avg(a.score) filter (where a.posttypeid = 2) as avg_answer_score,
         max(a.score) filter (where a.posttypeid = 2) as max_answer_score,
         min(a.creationdate) filter (where a.posttypeid = 2) as first_answer_time,
         max(a.creationdate) filter (where a.posttypeid = 2) as last_answer_time,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_on_q,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_on_q,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_on_q
  from recent_posts p
  left join posts a on a.parentid = p.id
  left join votes v on v.postid = p.id
  where p.posttypeid = 1
  group by p.id, p.owneruserid, p.score, p.viewcount, p.creationdate, p.acceptedanswerid
),
answer_stats as (
  select a.parentid as question_id,
         count(*) as answers_total,
         count(*) filter (where a.owneruserid is null) as answers_from_deleted_users,
         count(*) filter (where a.score > 0) as answers_positive,
         count(*) filter (where a.score < 0) as answers_negative,
         sum(a.score) as answers_score_sum
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= (select max(creationdate) - interval '365 days' from posts)
  group by a.parentid
),
tag_explode as (
  select p.id as post_id,
         lower(trim(both from t)) as tag
  from recent_posts p,
       lateral (
         select unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,'')) - 2, 0)), '><')) as t
       ) as u
),
question_tag_rank as (
  select te.post_id as question_id,
         te.tag,
         row_number() over (partition by te.post_id order by tg.count desc nulls last, te.tag) as tag_popularity_rank
  from tag_explode te
  left join tags tg on tg.tagname = te.tag
),
dup_links as (
  select pl.postid as question_id,
         count(*) filter (where pl.linktypeid = 3) as duplicate_links,
         count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  group by pl.postid
),
close_events as (
  select ph.postid as question_id,
         min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_close_time,
         max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopen_time,
         count(*) filter (where ph.posthistorytypeid = 10) as close_votes_count,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_votes_count,
         max(case when ph.posthistorytypeid = 10 then cast(ph.comment as integer) end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
accepted_answer_latency as (
  select q.id as question_id,
         q.creationdate as q_created,
         a.id as answer_id,
         a.creationdate as a_created,
         extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
),
user_badge_rollup as (
  select b.userid,
         count(*) as badges_total,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(*) filter (where b.tagbased = true) as tag_badges
  from badges b
  group by b.userid
),
post_engagement as (
  select p.id as post_id,
         coalesce(sum(c.score),0) as comment_score_sum,
         count(c.id) as comment_count,
         avg(c.score) as comment_avg_score,
         max(c.creationdate) as last_comment_time
  from posts p
  left join comments c on c.postid = p.id
  group by p.id
),
views_percentile as (
  select p.id as post_id,
         p.viewcount,
         ntile(100) over (order by coalesce(p.viewcount,0) nulls first) as view_ntile,
         percent_rank() over (order by coalesce(p.viewcount,0) nulls first) as view_percent_rank
  from recent_posts p
),
user_reputation_band as (
  select u.id as userid,
         case
           when u.reputation >= 100000 then 'legend'
           when u.reputation >= 25000 then 'expert'
           when u.reputation >= 5000 then 'pro'
           when u.reputation >= 1000 then 'intermediate'
           when u.reputation >= 100 then 'beginner'
           else 'newbie'
         end as rep_band
  from users u
),
question_quality_score as (
  select qm.question_id,
         coalesce(qm.q_score,0) * 0.5
         + coalesce(qm.q_views,0) * 0.001
         + coalesce(as2.answers_total,0) * 1.5
         + coalesce(qm.upvotes_on_q,0) * 0.75
         - coalesce(qm.downvotes_on_q,0) * 0.9
         + case when qm.acceptedanswerid is not null then 5 else 0 end
         - coalesce(ce.close_votes_count,0) * 2
         + coalesce(dl.related_links,0) * 0.2
         - coalesce(dl.duplicate_links,0) * 1.2
         + coalesce(pe.comment_count,0) * 0.1
         + coalesce(vp.view_percent_rank,0) * 10
         + coalesce(aa.hours_to_accept, 48) * (-0.05)
         as quality_score
  from question_metrics qm
  left join answer_stats as2 on as2.question_id = qm.question_id
  left join dup_links dl on dl.question_id = qm.question_id
  left join close_events ce on ce.question_id = qm.question_id
  left join post_engagement pe on pe.post_id = qm.question_id
  left join views_percentile vp on vp.post_id = qm.question_id
  left join accepted_answer_latency aa on aa.question_id = qm.question_id
),
ranked_questions as (
  select qm.question_id,
         qm.asker_id,
         qm.q_score,
         qm.q_views,
         qm.answer_count,
         qm.avg_answer_score,
         qm.max_answer_score,
         qm.first_answer_time,
         qm.last_answer_time,
         coalesce(ce.first_close_time, qm.q_created) as first_close_time,
         ce.last_reopen_time,
         ce.close_votes_count,
         ce.reopen_votes_count,
         ce.last_close_reason_id,
         dl.duplicate_links,
         dl.related_links,
         qqs.quality_score,
         dense_rank() over (order by qqs.quality_score desc nulls last, qm.q_views desc nulls last, qm.q_score desc nulls last) as quality_rank
  from question_metrics qm
  left join dup_links dl on dl.question_id = qm.question_id
  left join close_events ce on ce.question_id = qm.question_id
  left join question_quality_score qqs on qqs.question_id = qm.question_id
),
asker_profile as (
  select ua.userid,
         ua.displayname,
         ua.reputation,
         ua.location,
         ua.post_count,
         ua.comment_count,
         ua.upvotes_cast,
         ua.downvotes_cast,
         ua.total_votes_cast,
         ub.badges_total,
         ub.gold_badges,
         ub.silver_badges,
         ub.bronze_badges,
         ub.tag_badges,
         urb.rep_band
  from user_activity ua
  left join user_badge_rollup ub on ub.userid = ua.userid
  left join user_reputation_band urb on urb.userid = ua.userid
),
top_tags_per_question as (
  select qtr.question_id,
         string_agg(qtr.tag, ', ' order by qtr.tag_popularity_rank asc) filter (where qtr.tag_popularity_rank <= 3) as top3_tags,
         count(*) as tag_count
  from question_tag_rank qtr
  group by qtr.question_id
),
null_posttype_sentinel as (
  select p.id as post_id,
         case when p.posttypeid is null then 1 else 0 end as is_null_posttype
  from posts p
)
select
  rq.question_id,
  coalesce(p.title, ('Question #' || cast(rq.question_id as varchar))) as title_or_fallback,
  p.creationdate as created_at,
  rq.q_score,
  rq.q_views,
  rq.answer_count,
  rq.avg_answer_score,
  rq.max_answer_score,
  rq.first_answer_time,
  rq.last_answer_time,
  rq.duplicate_links,
  rq.related_links,
  rq.close_votes_count,
  rq.reopen_votes_count,
  rq.first_close_time,
  rq.last_reopen_time,
  rq.last_close_reason_id,
  ttpq.top3_tags,
  ttpq.tag_count,
  ap.displayname as asker_name,
  ap.reputation as asker_reputation,
  ap.location as asker_location,
  ap.post_count as asker_posts_total,
  ap.comment_count as asker_comments_total,
  ap.badges_total as asker_badges_total,
  ap.gold_badges,
  ap.silver_badges,
  ap.bronze_badges,
  ap.tag_badges,
  ap.upvotes_cast as asker_upvotes_cast,
  ap.downvotes_cast as asker_downvotes_cast,
  ap.total_votes_cast as asker_total_votes_cast,
  qqs.quality_score,
  rq.quality_rank,
  vp.view_percent_rank,
  pe.comment_score_sum,
  pe.comment_count as total_comments,
  pe.comment_avg_score,
  pe.last_comment_time,
  case
    when nq.is_null_posttype = 1 then 'Orphan'
    when p.posttypeid = 1 then 'Question'
    when p.posttypeid = 2 then 'AnswerParent?'
    else 'Other'
  end as posttype_label,
  case when p.closeddate is not null then true else false end as is_closed,
  case when p.communityowneddate is not null then true else false end as is_community_owned
from ranked_questions rq
join posts p on p.id = rq.question_id
left join question_quality_score qqs on qqs.question_id = rq.question_id
left join top_tags_per_question ttpq on ttpq.question_id = rq.question_id
left join asker_profile ap on ap.userid = rq.asker_id
left join post_engagement pe on pe.post_id = rq.question_id
left join views_percentile vp on vp.post_id = rq.question_id
left join null_posttype_sentinel nq on nq.post_id = rq.question_id
where
  coalesce(rq.q_views,0) >= (
    select percentile_disc(0.75) within group (order by coalesce(viewcount,0))
    from recent_posts
    where posttypeid = 1
  )
  and (
    rq.answer_count >= 1
    or exists (
      select 1
      from posts a
      where a.parentid = rq.question_id
        and a.posttypeid = 2
        and a.score >= all (
          select coalesce(score, -2147483648)
          from posts a2
          where a2.parentid = rq.question_id
            and a2.posttypeid = 2
        )
    )
  )
  and not exists (
    select 1
    from posthistory ph
    where ph.postid = rq.question_id
      and ph.posthistorytypeid = 12
  )
order by rq.quality_rank asc, rq.q_views desc
limit 250;