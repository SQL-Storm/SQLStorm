-- {"query": "450.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2867} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    u.views,
    u.upvotes,
    u.downvotes,
    dense_rank() over (order by date_trunc('month', u.creationdate) desc, u.id) as recency_bucket
  from users u
  where u.creationdate >= now() - interval '5 years'
),
user_badge_rollup as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_date,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
q as (
  select
    p.id as question_id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.title,
    p.tags,
    (select count(*) from comments c where c.postid = p.id) as comment_count,
    case
      when p.closeddate is not null then 1
      when exists (
        select 1
        from posthistory ph
        where ph.postid = p.id
          and ph.posthistorytypeid in (10,11) -- closed/reopened
      ) then 1
      else 0
    end as has_close_activity
  from posts p
  where p.posttypeid = 1
),
a as (
  select
    pa.parentid as question_id,
    pa.id as answer_id,
    pa.owneruserid as answerer_id,
    pa.score as answer_score,
    pa.creationdate as answer_date,
    row_number() over (partition by pa.parentid order by pa.score desc nulls last, pa.creationdate asc, pa.id) as answer_rank_by_score
  from posts pa
  where pa.posttypeid = 2
),
 accepted_answer as (
  select
    p.id as question_id,
    p.acceptedanswerid as answer_id
  from posts p
  where p.posttypeid = 1
    and p.acceptedanswerid is not null
),
 close_reasons as (
  select
    ph.postid as question_id,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
    max(crt.name) filter (where ph.posthistorytypeid = 10) as last_close_reason_name,
    max(ph.comment) filter (where ph.posthistorytypeid = 10) as last_close_reason_id_raw
  from posthistory ph
  left join closereasontypes crt
    on crt.id::varchar = nullif(ph.comment, '')
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
 vote_rollup as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
 link_dupes as (
  select
    pl.postid as question_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  group by pl.postid
),
 tag_explode as (
  select
    q.question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from q
  where q.tags is not null
),
 tag_stats as (
  select
    te.question_id,
    count(*) as tag_count,
    string_agg(te.tagname, ',' order by te.tagname) as tag_list,
    sum(case when lower(te.tagname) like any (array['%sql%','%postgres%','%mysql%','%sqlite%']) then 1 else 0 end) as sqlish_tag_hits
  from tag_explode te
  group by te.question_id
),
 user_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as questions_posted,
    count(*) filter (where p.posttypeid = 2) as answers_posted,
    max(p.lastactivitydate) as last_post_activity,
    sum(coalesce(p.score,0)) as total_post_score
  from users u
  left join posts p
    on p.owneruserid = u.id
  group by u.id
),
 comment_rollup as (
  select
    c.postid,
    count(*) as comments_count,
    max(c.creationdate) as last_comment_at,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments
  from comments c
  group by c.postid
),
 ranked_questions as (
  select
    q.question_id,
    q.owneruserid,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    q.title,
    q.tags,
    q.comment_count,
    q.has_close_activity,
    coalesce(vr.upvotes,0) as upvotes,
    coalesce(vr.downvotes,0) as downvotes,
    coalesce(vr.bounty_started,0) as bounty_started,
    coalesce(vr.bounty_awarded,0) as bounty_awarded,
    lr.duplicate_links,
    lr.related_links,
    ts.tag_count,
    ts.tag_list,
    ts.sqlish_tag_hits,
    cr.last_closed_at,
    cr.last_close_reason_name,
    cr.last_close_reason_id_raw,
    ca.comments_count as comments_from_table,
    ca.last_comment_at,
    coalesce(a_top.answer_id, -1) as top_answer_id,
    a_top.answer_score as top_answer_score,
    case when aa.answer_id is not null then 1 else 0 end as has_accepted_answer,
    row_number() over (
      order by
        coalesce(q.score,0) desc,
        coalesce(vr.upvotes,0) - coalesce(vr.downvotes,0) desc,
        coalesce(q.viewcount,0) desc,
        q.creationdate desc
    ) as global_rank
  from q
  left join vote_rollup vr on vr.postid = q.question_id
  left join link_dupes lr on lr.question_id = q.question_id
  left join tag_stats ts on ts.question_id = q.question_id
  left join close_reasons cr on cr.question_id = q.question_id
  left join comment_rollup ca on ca.postid = q.question_id
  left join a a_top
    on a_top.question_id = q.question_id
   and a_top.answer_rank_by_score = 1
  left join accepted_answer aa
    on aa.question_id = q.question_id
),
 user_enriched as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location_norm,
    ru.creationdate as user_created,
    ru.views,
    ru.upvotes as user_upvotes,
    ru.downvotes as user_downvotes,
    ru.recency_bucket,
    coalesce(ubr.total_badges,0) as total_badges,
    coalesce(ubr.gold_badges,0) as gold_badges,
    coalesce(ubr.silver_badges,0) as silver_badges,
    coalesce(ubr.bronze_badges,0) as bronze_badges,
    ubr.last_badge_date,
    coalesce(ubr.tag_badges,0) as tag_badges,
    ua.questions_posted,
    ua.answers_posted,
    ua.last_post_activity,
    ua.total_post_score
  from recent_users ru
  left join user_badge_rollup ubr on ubr.userid = ru.user_id
  left join user_activity ua on ua.user_id = ru.user_id
),
 per_user_question as (
  select
    rq.*,
    ue.user_id,
    ue.displayname,
    ue.reputation,
    ue.location_norm,
    ue.user_created,
    ue.recency_bucket,
    ue.total_badges,
    ue.gold_badges,
    ue.silver_badges,
    ue.bronze_badges,
    ue.tag_badges,
    ue.questions_posted,
    ue.answers_posted,
    ue.total_post_score,
    dense_rank() over (
      partition by ue.user_id
      order by rq.score desc nulls last, rq.viewcount desc nulls last, rq.creationdate desc
    ) as per_user_rank
  from ranked_questions rq
  left join user_enriched ue
    on ue.user_id = rq.owneruserid
  where rq.creationdate >= now() - interval '3 years'
),
 heavy_calc as (
  select
    puq.*,
    coalesce(puq.upvotes,0) - coalesce(puq.downvotes,0) as net_votes,
    case
      when puq.answercount > 0 then puq.viewcount::numeric / puq.answercount
      else null
    end as views_per_answer,
    case
      when puq.tag_count is null or puq.tag_count = 0 then 0
      else round(100.0 * puq.sqlish_tag_hits / puq.tag_count, 2)
    end as sqlish_tag_pct,
    case
      when puq.has_accepted_answer = 1 then 'Accepted'
      when puq.top_answer_score is not null and puq.top_answer_score >= greatest(5, coalesce(puq.score,0)/2) then 'HighTopAnswer'
      when puq.answercount = 0 then 'Unanswered'
      when puq.has_close_activity = 1 then 'ClosedOrReopened'
      else 'Other'
    end as q_status_bucket,
    case
      when puq.last_closed_at is not null then extract(epoch from (now() - puq.last_closed_at))::bigint
      else null
    end as secs_since_closed,
    md5(coalesce(lower(trim(puq.title)), '')) as title_fingerprint
  from per_user_question puq
),
 final_rank as (
  select
    hc.*,
    row_number() over (
      partition by coalesce(hc.location_norm,'Unknown')
      order by
        (coalesce(hc.net_votes,0) + coalesce(hc.bounty_awarded,0)/100.0 + coalesce(hc.favoritecount,0)) desc,
        hc.viewcount desc,
        hc.creationdate desc
    ) as place_in_location,
    row_number() over (
      partition by hc.recency_bucket
      order by hc.global_rank
    ) as place_in_recency_bucket
  from heavy_calc hc
)
select
  fr.question_id,
  coalesce(fr.title, '(no title)') as title,
  fr.owneruserid as owner_user_id,
  coalesce(fr.displayname, '(deleted user)') as owner_name,
  fr.reputation,
  fr.location_norm,
  fr.user_created,
  fr.creationdate as question_created,
  fr.score,
  fr.upvotes,
  fr.downvotes,
  fr.net_votes,
  fr.viewcount,
  fr.answercount,
  fr.favoritecount,
  fr.comment_count,
  fr.comments_from_table,
  fr.last_comment_at,
  fr.tag_count,
  fr.tag_list,
  fr.sqlish_tag_pct,
  fr.q_status_bucket,
  fr.last_closed_at,
  coalesce(fr.last_close_reason_name, 'Unknown') as last_close_reason_name,
  fr.last_close_reason_id_raw,
  fr.top_answer_id,
  fr.top_answer_score,
  fr.has_accepted_answer,
  fr.duplicate_links,
  fr.related_links,
  fr.bounty_started,
  fr.bounty_awarded,
  fr.first_vote_at,
  fr.last_vote_at,
  fr.per_user_rank,
  fr.global_rank,
  fr.place_in_location,
  fr.place_in_recency_bucket
from final_rank fr
where
  (
    fr.recency_bucket <= 12
    and fr.place_in_recency_bucket <= 100
  )
  or
  (
    fr.place_in_location <= 25
    and coalesce(fr.net_votes,0) >= 5
  )
  or
  (
    fr.q_status_bucket in ('Unanswered','HighTopAnswer')
    and fr.viewcount >= 1000
  )
order by
  fr.global_rank,
  fr.place_in_location nulls last,
  fr.place_in_recency_bucket nulls last,
  fr.question_created desc
limit 1000;