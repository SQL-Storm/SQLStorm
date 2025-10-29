-- {"query": "246.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3025} 
with
recent_users as (
  select u.id as user_id,
         u.displayname,
         u.creationdate,
         u.reputation,
         coalesce(u.location, 'Unknown') as location,
         dense_rank() over (order by date_trunc('month', u.creationdate) desc, u.reputation desc) as cohort_rank
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
question_activity as (
  select p.id as question_id,
         p.owneruserid as asker_id,
         p.creationdate as asked_at,
         p.score as q_score,
         p.viewcount,
         p.answercount,
         p.favoritecount,
         p.closeddate,
         p.tags,
         p.acceptedanswerid,
         count(c.id) filter (where c.id is not null) as comment_count,
         sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
         max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_at,
         bool_or(ph.posthistorytypeid = 10) as ever_closed_flag
  from posts p
  left join comments c on c.postid = p.id
  left join votes v on v.postid = p.id
  left join posthistory ph on ph.postid = p.id
  where p.posttypeid = 1
    and p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
  group by p.id, p.owneruserid, p.creationdate, p.score, p.viewcount, p.answercount, p.favoritecount, p.closeddate, p.tags, p.acceptedanswerid
),
answer_activity as (
  select a.parentid as question_id,
         count(*) as answers_total,
         sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
         max(a.creationdate) as last_answer_at,
         min(a.creationdate) as first_answer_at
  from posts a
  where a.posttypeid = 2
  group by a.parentid
),
dup_links as (
  select pl.postid as question_id,
         count(*) filter (where pl.linktypeid = 3) as dup_count,
         max(pl.creationdate) filter (where pl.linktypeid = 3) as last_dup_at
  from postlinks pl
  group by pl.postid
),
hot_spikes as (
  select qa.question_id,
         qa.asked_at,
         qa.viewcount,
         qa.net_votes,
         qa.comment_count,
         lag(qa.viewcount) over (order by qa.asked_at) as prev_views,
         lag(qa.net_votes) over (order by qa.asked_at) as prev_net_votes,
         lag(qa.comment_count) over (order by qa.asked_at) as prev_comments
  from question_activity qa
),
accepted_latency as (
  select q.id as question_id,
         q.acceptedanswerid,
         a.creationdate as accepted_at,
         q.creationdate as asked_at,
         extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
  from posts q
  left join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
),
tag_expansion as (
  select qa.question_id,
         unnest(string_to_array(substring(qa.tags, 2, greatest(length(qa.tags)-2,0)), '><')) as tag
  from question_activity qa
  where qa.tags is not null
),
tag_stats as (
  select te.tag,
         count(*) as tag_q_count,
         avg(qa.viewcount::numeric) as tag_avg_views,
         avg(qa.q_score::numeric) as tag_avg_qscore
  from tag_expansion te
  join question_activity qa on qa.question_id = te.question_id
  group by te.tag
),
user_badge_summary as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold,
         sum(case when b.class = 2 then 1 else 0 end) as silver,
         sum(case when b.class = 3 then 1 else 0 end) as bronze,
         count(*) as total_badges,
         max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
user_engagement as (
  select u.id as user_id,
         count(distinct p.id) filter (where p.posttypeid = 1) as questions_asked,
         count(distinct p.id) filter (where p.posttypeid = 2) as answers_posted,
         count(distinct c.id) as comments_made,
         sum(coalesce(v.delta,0)) as voting_delta
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join (
    select v.userid, sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as delta
    from votes v
    group by v.userid
  ) v on v.userid = u.id
  group by u.id
),
question_quality as (
  select qa.question_id,
         qa.q_score,
         qa.viewcount,
         qa.answercount,
         qa.comment_count,
         qa.net_votes,
         aa.answers_total,
         aa.answers_positive,
         coalesce(als.hours_to_accept, null) as hours_to_accept,
         coalesce(dl.dup_count, 0) as dup_count,
         coalesce(case when qa.viewcount > 0 then (qa.net_votes::numeric / qa.viewcount) else null end, 0) as votes_per_view,
         case
           when qa.closeddate is not null then 'Closed'
           when aa.answers_total is null or aa.answers_total = 0 then 'Unanswered'
           when als.acceptedanswerid is not null then 'Accepted'
           else 'Answered'
         end as status_label
  from question_activity qa
  left join answer_activity aa on aa.question_id = qa.question_id
  left join dup_links dl on dl.question_id = qa.question_id
  left join accepted_latency als on als.question_id = qa.question_id
),
post_close_reasons as (
  select ph.postid as question_id,
         max(case
               when ph.posthistorytypeid = 10 then
                 nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '')
             end)::int as last_close_reason_id,
         max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at
  from posthistory ph
  group by ph.postid
),
close_reason_names as (
  select crt.id, crt.name from closereasontypes crt
),
question_rank as (
  select qq.question_id,
         dense_rank() over (order by
            coalesce(qq.votes_per_view,0) desc,
            coalesce(qq.answers_positive,0) desc,
            coalesce(qq.q_score,0) desc,
            coalesce(qq.viewcount,0) desc
         ) as quality_rank,
         row_number() over (order by coalesce(qq.viewcount,0) desc) as views_rank,
         ntile(10) over (order by coalesce(qq.net_votes,0) desc) as votes_decile
  from question_quality qq
),
question_owner as (
  select p.id as question_id,
         p.owneruserid as user_id
  from posts p
  where p.posttypeid = 1
),
owner_profile as (
  select qo.question_id,
         u.id as user_id,
         u.displayname,
         u.reputation,
         ue.questions_asked,
         ue.answers_posted,
         ue.comments_made,
         ue.voting_delta,
         coalesce(ubs.total_badges,0) as total_badges,
         coalesce(ubs.gold,0) as gold,
         coalesce(ubs.silver,0) as silver,
         coalesce(ubs.bronze,0) as bronze,
         ru.location,
         ru.cohort_rank,
         case when u.websiteurl is null or trim(u.websiteurl) = '' then 0 else 1 end as has_website
  from question_owner qo
  left join users u on u.id = qo.user_id
  left join recent_users ru on ru.user_id = u.id
  left join user_badge_summary ubs on ubs.userid = u.id
  left join user_engagement ue on ue.user_id = u.id
),
question_time_dims as (
  select p.id as question_id,
         date_trunc('day', p.creationdate) as day_bucket,
         date_trunc('week', p.creationdate) as week_bucket,
         date_trunc('month', p.creationdate) as month_bucket
  from posts p
  where p.posttypeid = 1
),
activity_windows as (
  select qa.question_id,
         qa.asked_at,
         qa.viewcount,
         qa.net_votes,
         qa.comment_count,
         sum(qa.viewcount) over (order by qa.asked_at rows between 10 preceding and current row) as rolling_11_views,
         avg(qa.net_votes::numeric) over (order by qa.asked_at rows between 10 preceding and current row) as rolling_11_netvotes_avg,
         sum(qa.comment_count) over (order by qa.asked_at rows between unbounded preceding and current row) as cum_comments
  from question_activity qa
),
question_flags as (
  select qa.question_id,
         case when hs.prev_views is not null and qa.viewcount >= hs.prev_views * 3 then 1 else 0 end as spike_views_flag,
         case when hs.prev_net_votes is not null and qa.net_votes - hs.prev_net_votes >= 10 then 1 else 0 end as spike_votes_flag,
         case when hs.prev_comments is not null and qa.comment_count > hs.prev_comments * 2 then 1 else 0 end as spike_comments_flag
  from question_activity qa
  left join hot_spikes hs on hs.question_id = qa.question_id
),
final_scores as (
  select qq.question_id,
         qr.quality_rank,
         qr.views_rank,
         qr.votes_decile,
         aq.rolling_11_views,
         aq.rolling_11_netvotes_avg,
         aq.cum_comments,
         qf.spike_views_flag + qf.spike_votes_flag + qf.spike_comments_flag as spike_score,
         (coalesce(qq.votes_per_view,0) * 0.5
          + coalesce(qq.answers_positive,0) * 0.3
          + case when qq.status_label = 'Accepted' then 1 else 0 end * 0.2
          - least(coalesce(qq.dup_count,0), 5) * 0.1) as blended_quality
  from question_quality qq
  left join question_rank qr on qr.question_id = qq.question_id
  left join activity_windows aq on aq.question_id = qq.question_id
  left join question_flags qf on qf.question_id = qq.question_id
)
select
  p.id as question_id,
  p.title,
  p.tags,
  qq.status_label,
  qq.q_score,
  qq.viewcount,
  qq.answercount,
  qq.comment_count,
  qq.net_votes,
  qq.dup_count,
  qq.hours_to_accept,
  crn.name as last_close_reason_name,
  pcr.last_closed_at,
  os.displayname as owner_displayname,
  os.reputation as owner_reputation,
  os.total_badges,
  os.gold,
  os.silver,
  os.bronze,
  os.questions_asked,
  os.answers_posted,
  os.comments_made,
  os.voting_delta,
  os.location,
  os.cohort_rank,
  os.has_website,
  ts.tag as top_tag_by_views,
  ts2.tag as top_tag_by_qscore,
  fs.quality_rank,
  fs.views_rank,
  fs.votes_decile,
  fs.rolling_11_views,
  fs.rolling_11_netvotes_avg,
  fs.cum_comments,
  fs.spike_score,
  fs.blended_quality,
  qt.day_bucket,
  qt.week_bucket,
  qt.month_bucket
from posts p
join question_quality qq on qq.question_id = p.id
left join post_close_reasons pcr on pcr.question_id = p.id
left join close_reason_names crn on crn.id = pcr.last_close_reason_id
left join owner_profile os on os.question_id = p.id
left join final_scores fs on fs.question_id = p.id
left join question_time_dims qt on qt.question_id = p.id
left join lateral (
  select ts.tag
  from tag_stats ts
  join tag_expansion te on te.tag = ts.tag and te.question_id = p.id
  order by ts.tag_avg_views desc nulls last, ts.tag_q_count desc nulls last
  limit 1
) ts on true
left join lateral (
  select ts.tag
  from tag_stats ts
  join tag_expansion te on te.tag = ts.tag and te.question_id = p.id
  order by ts.tag_avg_qscore desc nulls last, ts.tag_q_count desc nulls last
  limit 1
) ts2 on true
where p.posttypeid = 1
  and coalesce(p.viewcount,0) + coalesce(p.score,0) + coalesce(p.answercount,0) > 0
  and (
    fs.blended_quality is null
    or fs.blended_quality >= (
      select percentile_cont(0.75) within group (order by coalesce(blended_quality,0))
      from final_scores
    )
  )
order by
  fs.quality_rank nulls last,
  fs.blended_quality desc nulls last,
  p.creationdate desc
limit 500;