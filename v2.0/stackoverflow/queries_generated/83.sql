-- {"query": "83.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3343} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.upvotes,
    u.downvotes,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    dense_rank() over (order by u.creationdate desc) as recency_rank
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from users)
),
question_posts as (
  select
    p.id as qid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.acceptedanswerid,
    p.closeddate,
    p.contentlicense,
    case when p.closeddate is not null then 1 else 0 end as is_closed
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select
    a.id as aid,
    a.parentid as qid,
    a.owneruserid as answererid,
    a.creationdate as a_creationdate,
    a.score as a_score
  from posts a
  where a.posttypeid = 2
),
badge_rollup as (
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
q_activity as (
  select
    q.qid,
    count(distinct c.id) filter (where c.id is not null) as comment_count,
    count(distinct v.id) filter (where v.id is not null and v.votetypeid = 2) as upvote_count,
    count(distinct v.id) filter (where v.id is not null and v.votetypeid = 3) as downvote_count,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorite_marks,
    max(coalesce(c.creationdate, v.creationdate, q.creationdate)) as last_interaction
  from question_posts q
  left join comments c on c.postid = q.qid
  left join votes v on v.postid = q.qid
  group by q.qid
),
dup_links as (
  select
    pl.postid as qid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  group by pl.postid
),
accepted_answerers as (
  select
    q.qid,
    a.answererid as accepted_user_id,
    row_number() over (partition by q.qid order by a.a_score desc, a.a_creationdate) as rn
  from question_posts q
  join posts aa on aa.id = q.acceptedanswerid
  join answer_posts a on a.aid = aa.id
),
user_agg as (
  select
    u.user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.upvotes,
    u.downvotes,
    u.websiteurl,
    u.recency_rank,
    br.total_badges,
    br.gold_badges,
    br.silver_badges,
    br.bronze_badges,
    br.first_badge_date,
    br.last_badge_date
  from recent_users u
  left join badge_rollup br on br.userid = u.user_id
),
q_metrics as (
  select
    q.qid,
    q.owneruserid,
    q.creationdate,
    q.score,
    q.viewcount,
    q.title,
    q.tags,
    q.answercount,
    q.acceptedanswerid,
    q.closeddate,
    q.is_closed,
    qa.comment_count,
    qa.upvote_count,
    qa.downvote_count,
    qa.favorite_marks,
    qa.last_interaction,
    coalesce(dl.duplicate_links, 0) as duplicate_links,
    coalesce(dl.related_links, 0) as related_links,
    case
      when q.viewcount is null or q.viewcount = 0 then null
      else round((q.score::numeric / nullif(q.viewcount, 0)) * 1000, 3)
    end as score_per_kview,
    case when qa.upvote_count + qa.downvote_count = 0 then null
         else round(qa.upvote_count::numeric / nullif(qa.upvote_count + qa.downvote_count, 0), 4)
    end as upvote_ratio
  from question_posts q
  left join q_activity qa on qa.qid = q.qid
  left join dup_links dl on dl.qid = q.qid
),
tag_explode as (
  select
    qm.qid,
    unnest(string_to_array(substring(qm.tags, 2, greatest(length(qm.tags)-2,0)), '><')) as tag
  from q_metrics qm
  where qm.tags is not null and qm.tags like '<%>'
),
tag_density as (
  select
    qid,
    count(*) as tag_count,
    string_agg(tag, '|' order by tag) as tag_concat
  from tag_explode
  group by qid
),
question_enriched as (
  select
    qm.*,
    td.tag_count,
    td.tag_concat,
    case
      when qm.title ilike any (array['%how to%', '%what is%', '%why%']) then 'Questioning'
      when qm.title ilike any (array['%best%', '%ultimate%', '%guide%']) then 'Guide-ish'
      else 'Other'
    end as title_style
  from q_metrics qm
  left join tag_density td on td.qid = qm.qid
),
answer_stats as (
  select
    a.qid,
    count(*) as answers_total,
    sum(case when a.a_score > 0 then 1 else 0 end) as answers_positive,
    max(a.a_score) as best_answer_score,
    min(a.a_score) as worst_answer_score,
    percentile_disc(0.5) within group (order by a.a_score) as median_answer_score
  from answer_posts a
  group by a.qid
),
accepted_map as (
  select qid, accepted_user_id
  from accepted_answerers
  where rn = 1
),
user_question_bridge as (
  select
    qe.qid,
    qe.owneruserid as user_id,
    qe.creationdate as q_created,
    qe.score,
    qe.viewcount,
    qe.answercount,
    qe.acceptedanswerid,
    qe.is_closed,
    qe.comment_count,
    qe.upvote_count,
    qe.downvote_count,
    qe.favorite_marks,
    qe.last_interaction,
    qe.duplicate_links,
    qe.related_links,
    qe.score_per_kview,
    qe.upvote_ratio,
    qe.tag_count,
    qe.tag_concat,
    qe.title_style,
    asx.answers_total,
    asx.answers_positive,
    asx.best_answer_score,
    asx.worst_answer_score,
    asx.median_answer_score,
    case when qe.acceptedanswerid is not null then 1 else 0 end as has_accepted,
    case when am.accepted_user_id = qe.owneruserid then 1 else 0 end as self_answer_accepted
  from question_enriched qe
  left join answer_stats asx on asx.qid = qe.qid
  left join accepted_map am on am.qid = qe.qid
),
user_roll as (
  select
    u.user_id,
    count(distinct uqb.qid) as questions_asked,
    sum(coalesce(uqb.viewcount,0)) as total_views,
    sum(coalesce(uqb.score,0)) as total_score,
    avg(nullif(uqb.score,0)) filter (where uqb.score is not null) as avg_score_nonzero,
    avg(uqb.score_per_kview) as avg_score_per_kview,
    sum(coalesce(uqb.comment_count,0)) as total_comments,
    sum(coalesce(uqb.favorite_marks,0)) as total_favorites,
    sum(coalesce(uqb.has_accepted,0)) as questions_with_accepted,
    sum(coalesce(uqb.self_answer_accepted,0)) as self_answer_accepted_cnt,
    avg(uqb.upvote_ratio) as avg_upvote_ratio,
    max(uqb.last_interaction) as last_interaction_any,
    max(case when uqb.is_closed = 1 then uqb.q_created end) as last_closed_q,
    sum(coalesce(uqb.duplicate_links,0)) as dup_links_sum,
    sum(coalesce(uqb.related_links,0)) as related_links_sum,
    count(*) filter (where coalesce(uqb.tag_count,0) > 5) as many_tags_q_cnt
  from user_agg u
  left join user_question_bridge uqb on uqb.user_id = u.user_id
  group by u.user_id
),
ranked_users as (
  select
    u.*,
    ur.questions_asked,
    ur.total_views,
    ur.total_score,
    ur.avg_score_nonzero,
    ur.avg_score_per_kview,
    ur.total_comments,
    ur.total_favorites,
    ur.questions_with_accepted,
    ur.self_answer_accepted_cnt,
    ur.avg_upvote_ratio,
    ur.last_interaction_any,
    ur.last_closed_q,
    ur.dup_links_sum,
    ur.related_links_sum,
    ur.many_tags_q_cnt,
    row_number() over (
      order by
        coalesce(ur.total_score,0) desc,
        coalesce(ur.total_views,0) desc,
        coalesce(u.reputation,0) desc
    ) as perf_rank
  from user_agg u
  left join user_roll ur on ur.user_id = u.user_id
),
post_hist_summary as (
  select
    ph.postid as qid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_count,
    count(*) filter (where ph.posthistorytypeid in (10)) as close_events,
    count(*) filter (where ph.posthistorytypeid in (11)) as reopen_events,
    min(ph.creationdate) as first_hist,
    max(ph.creationdate) as last_hist,
    sum(case
          when ph.posthistorytypeid = 10
               and coalesce(nullif(trim(ph.comment), ''), '0') ~ '^[0-9]+$'
          then 1 else 0 end) as close_reason_noted
  from posthistory ph
  group by ph.postid
),
final_scored as (
  select
    ru.*,
    pq.qid,
    pq.q_created,
    pq.score,
    pq.viewcount,
    pq.answercount,
    pq.comment_count,
    pq.tag_count,
    pq.tag_concat,
    pq.title_style,
    phs.edits_count,
    phs.close_events,
    phs.reopen_events,
    coalesce(phs.close_reason_noted,0) as close_reason_noted,
    -- composite score emphasizing questions with engagement, normalized by recency and badges
    round(
      (
        coalesce(pq.score,0)*2
        + coalesce(pq.comment_count,0)*0.5
        + coalesce(pq.viewcount,0)::numeric/1000
        + coalesce(pq.answercount,0)*1.2
        + coalesce(phs.edits_count,0)*0.3
        - coalesce(phs.close_events,0)*1.5
      )
      *
      (1 + least(coalesce(ru.total_badges,0), 50)::numeric/200)
      /
      nullif(greatest(ru.recency_rank,1),0)
    ,3) as composite_score
  from ranked_users ru
  left join user_question_bridge pq on pq.user_id = ru.user_id
  left join post_hist_summary phs on phs.qid = pq.qid
),
bucketed as (
  select
    fs.*,
    ntile(10) over (partition by (case when fs.questions_asked is null or fs.questions_asked = 0 then 0 else 1 end)
                    order by fs.composite_score nulls last) as decile,
    case
      when fs.tag_concat ilike '%performance%' or fs.title_style = 'Guide-ish' then 'Perf/Guide'
      when coalesce(fs.tag_count,0) >= 5 then 'Heavy-Tagged'
      when coalesce(fs.answercount,0) = 0 then 'Unanswered'
      when fs.close_events > 0 then 'Closed-ish'
      else 'General'
    end as category
  from final_scored fs
)
select
  b.user_id,
  coalesce(b.displayname, '(unknown)') as displayname,
  b.reputation,
  b.questions_asked,
  b.total_views,
  b.total_score,
  b.total_comments,
  b.total_favorites,
  coalesce(b.total_badges,0) as total_badges,
  coalesce(b.gold_badges,0) as gold_badges,
  coalesce(b.silver_badges,0) as silver_badges,
  coalesce(b.bronze_badges,0) as bronze_badges,
  b.perf_rank,
  b.qid,
  coalesce(b.title_style,'Other') as title_style,
  coalesce(b.category,'General') as category,
  coalesce(b.tag_concat,'') as tag_concat,
  b.score,
  b.viewcount,
  b.answercount,
  b.comment_count,
  coalesce(b.edits_count,0) as edits_count,
  coalesce(b.close_events,0) as close_events,
  coalesce(b.reopen_events,0) as reopen_events,
  b.close_reason_noted,
  b.composite_score,
  b.decile,
  -- complicated predicate demo: flag "interesting" rows with multiple conditions
  case
    when b.composite_score is not null
     and b.decile <= 3
     and (b.close_events = 0 or b.reopen_events > 0)
     and (b.tag_concat ilike '%sql%' or (b.upvote_ratio is not null and b.upvote_ratio > 0.8))
     and (b.viewcount is null or b.viewcount > 100)
    then 1 else 0
  end as is_interesting
from bucketed b
where
  -- set operator inspired filter via EXISTS with UNION ALL semantics
  exists (
    select 1
    from (
      select u1.user_id from ranked_users u1 where u1.perf_rank <= 200
      union
      select u2.user_id from ranked_users u2 where coalesce(u2.total_score,0) > 500
    ) s
    where s.user_id = b.user_id
  )
  and (
    b.q_created is null
    or b.q_created >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
  )
order by b.decile, b.composite_score desc nulls last, b.perf_rank, b.user_id, b.qid nulls last
limit 500;