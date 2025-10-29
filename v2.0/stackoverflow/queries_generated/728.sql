-- {"query": "728.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3762} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'none') as websiteurl_norm,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_newest
  from users u
  where u.creationdate >= (select max(creationdate) - interval '2 years' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score, 0)) as total_post_score,
    sum(coalesce(p.viewcount, 0)) as total_views,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
comments_by_user as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(c.score) as comment_score_sum,
    avg(c.score) as comment_score_avg
  from comments c
  where c.userid is not null
  group by c.userid
),
votes_by_user as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounties_touch,
    sum(coalesce(case when v.votetypeid in (8,9) then v.bountyamount end, 0)) as bounty_amount_sum
  from votes v
  where v.userid is not null
  group by v.userid
),
badges_by_user as (
  select
    b.userid as user_id,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  group by b.userid
),
questions as (
  select
    p.id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.answercount,
    p.closeddate
  from posts p
  where p.posttypeid = 1
),
answers as (
  select
    p.id,
    p.parentid as question_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score
  from posts p
  where p.posttypeid = 2
),
first_answer_per_question as (
  select
    a.question_id,
    min(a.creationdate) as first_answer_time
  from answers a
  group by a.question_id
),
question_metrics as (
  select
    q.id as question_id,
    q.user_id,
    q.creationdate as q_created,
    q.score as q_score,
    q.viewcount as q_views,
    q.answercount,
    q.acceptedanswerid,
    q.closeddate,
    case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
    case when q.closeddate is not null then 1 else 0 end as is_closed,
    extract(epoch from (fa.first_answer_time - q.creationdate))::bigint as seconds_to_first_answer
  from questions q
  left join first_answer_per_question fa on fa.question_id = q.id
),
per_user_q_agg as (
  select
    qm.user_id,
    count(*) as questions_asked,
    avg(qm.q_score) as avg_q_score,
    percentile_cont(0.5) within group (order by qm.q_views) as med_q_views,
    avg(nullif(qm.seconds_to_first_answer, null)) as avg_secs_first_answer,
    sum(qm.has_accepted) as accepted_count,
    sum(qm.is_closed) as closed_count
  from question_metrics qm
  group by qm.user_id
),
accepted_answerers as (
  select
    a.user_id,
    count(*) as accepted_answers_given,
    avg(a.score) as avg_accepted_answer_score
  from answers a
  join posts q on q.id = a.question_id and q.acceptedanswerid = a.id
  group by a.user_id
),
tag_exploded as (
  select
    q.id as question_id,
    q.user_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags) - 2), '><')) as tag
  from questions q
  where q.tags is not null and length(q.tags) > 2
),
top_tags_per_user as (
  select user_id, tag, cnt,
         row_number() over (partition by user_id order by cnt desc, tag asc) as rn
  from (
    select user_id, tag, count(*) as cnt
    from tag_exploded
    group by user_id, tag
  ) s
),
dup_links as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as original_post_id
  from postlinks pl
  where pl.linktypeid = 3
),
dup_activity as (
  select
    q.user_id,
    count(*) as dup_marked_questions,
    count(distinct d.original_post_id) as distinct_originals_referenced
  from dup_links d
  join posts q on q.id = d.dup_post_id and q.posttypeid = 1
  group by q.user_id
),
edit_events as (
  select
    ph.postid,
    ph.userid as editor_user_id,
    ph.posthistorytypeid,
    ph.creationdate
  from posthistory ph
  where ph.posthistorytypeid in (4,5,6,24) and ph.userid is not null
),
edit_stats_by_user as (
  select
    e.editor_user_id as user_id,
    count(*) as edits_made,
    count(*) filter (where e.posthistorytypeid = 24) as suggested_edits_applied,
    min(e.creationdate) as first_edit_at,
    max(e.creationdate) as last_edit_at
  from edit_events e
  group by e.editor_user_id
),
hot_question_bumps as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid = 52 then 1 else 0 end) as became_hot,
    max(case when ph.posthistorytypeid = 53 then 1 else 0 end) as removed_hot
  from posthistory ph
  where ph.posthistorytypeid in (52,53)
  group by ph.postid
),
user_hotness as (
  select
    p.owneruserid as user_id,
    count(*) filter (where hq.became_hot = 1) as hot_q_count,
    count(*) filter (where hq.removed_hot = 1) as removed_hot_q_count
  from hot_question_bumps hq
  join posts p on p.id = hq.postid and p.posttypeid = 1
  group by p.owneruserid
),
activity_union as (
  select user_id, 'post' as kind, last_post_activity as last_activity
  from user_activity
  union all
  select user_id, 'edit', last_edit_at
  from edit_stats_by_user
  union all
  select user_id, 'comment', max(c.creationdate)
  from comments c
  where c.userid is not null
  group by user_id
),
last_activity_ranked as (
  select
    user_id,
    max(last_activity) as last_activity_at,
    row_number() over (order by max(last_activity) desc nulls last) as recency_rank
  from activity_union
  group by user_id
),
user_reputation_delta as (
  select
    u.id as user_id,
    u.reputation as current_rep,
    coalesce(ua.total_post_score, 0) + coalesce(vu.upvotes_cast, 0) * 10 - coalesce(vu.downvotes_cast, 0) * 2 as rough_activity_points
  from users u
  left join user_activity ua on ua.user_id = u.id
  left join votes_by_user vu on vu.user_id = u.id
),
filtered_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ru.location,
    ru.websiteurl_norm,
    case
      when coalesce(ua.q_count,0) + coalesce(ua.a_count,0) >= 50 then 'Power'
      when coalesce(ua.q_count,0) + coalesce(ua.a_count,0) >= 10 then 'Active'
      when coalesce(ua.q_count,0) + coalesce(ua.a_count,0) >= 1 then 'Casual'
      else 'Lurker'
    end as activity_tier
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  where ru.rn_newest <= 5000
),
composite as (
  select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.cohort_month,
    fu.location,
    fu.websiteurl_norm,
    fu.activity_tier,
    coalesce(ua.q_count, 0) as q_count,
    coalesce(ua.a_count, 0) as a_count,
    coalesce(ua.total_post_score, 0) as total_post_score,
    coalesce(ua.total_views, 0) as total_views,
    coalesce(cb.comment_count, 0) as comment_count,
    coalesce(cb.comment_score_sum, 0) as comment_score_sum,
    cb.comment_score_avg,
    coalesce(vu.upvotes_cast, 0) as upvotes_cast,
    coalesce(vu.downvotes_cast, 0) as downvotes_cast,
    coalesce(vu.bounties_touch, 0) as bounties_touch,
    coalesce(vu.bounty_amount_sum, 0) as bounty_amount_sum,
    coalesce(bu.total_badges, 0) as total_badges,
    coalesce(bu.gold_badges, 0) as gold_badges,
    coalesce(bu.silver_badges, 0) as silver_badges,
    coalesce(bu.bronze_badges, 0) as bronze_badges,
    coalesce(bu.tag_badges, 0) as tag_badges,
    coalesce(puq.questions_asked, 0) as questions_asked,
    puq.avg_q_score,
    puq.med_q_views,
    puq.avg_secs_first_answer,
    coalesce(puq.accepted_count, 0) as accepted_q_count,
    coalesce(puq.closed_count, 0) as closed_q_count,
    coalesce(aa.accepted_answers_given, 0) as accepted_answers_given,
    aa.avg_accepted_answer_score,
    coalesce(du.dup_marked_questions, 0) as dup_marked_questions,
    coalesce(du.distinct_originals_referenced, 0) as distinct_originals_referenced,
    coalesce(es.edits_made, 0) as edits_made,
    coalesce(es.suggested_edits_applied, 0) as suggested_edits_applied,
    es.first_edit_at,
    es.last_edit_at,
    coalesce(uh.hot_q_count, 0) as hot_q_count,
    coalesce(uh.removed_hot_q_count, 0) as removed_hot_q_count,
    lar.last_activity_at,
    lar.recency_rank,
    urd.current_rep,
    urd.rough_activity_points
  from filtered_users fu
  left join user_activity ua on ua.user_id = fu.user_id
  left join comments_by_user cb on cb.user_id = fu.user_id
  left join votes_by_user vu on vu.user_id = fu.user_id
  left join badges_by_user bu on bu.user_id = fu.user_id
  left join per_user_q_agg puq on puq.user_id = fu.user_id
  left join accepted_answerers aa on aa.user_id = fu.user_id
  left join dup_activity du on du.user_id = fu.user_id
  left join edit_stats_by_user es on es.user_id = fu.user_id
  left join user_hotness uh on uh.user_id = fu.user_id
  left join last_activity_ranked lar on lar.user_id = fu.user_id
  left join user_reputation_delta urd on urd.user_id = fu.user_id
),
top_tag_pivot as (
  select
    t.user_id,
    max(case when t.rn = 1 then t.tag end) as top_tag_1,
    max(case when t.rn = 2 then t.tag end) as top_tag_2,
    max(case when t.rn = 3 then t.tag end) as top_tag_3
  from top_tags_per_user t
  where t.rn <= 3
  group by t.user_id
),
ranked as (
  select
    c.*,
    ttp.top_tag_1,
    ttp.top_tag_2,
    ttp.top_tag_3,
    case
      when c.reputation >= 20000 then 'Legend'
      when c.reputation >= 10000 then 'Veteran'
      when c.reputation >= 2000 then 'Experienced'
      when c.reputation >= 200 then 'Rising'
      else 'Newbie'
    end as rep_bucket,
    row_number() over (
      partition by c.activity_tier
      order by
        coalesce(c.total_post_score,0) * 2
        + coalesce(c.upvotes_cast,0) * 10
        - coalesce(c.downvotes_cast,0) * 2
        + coalesce(c.total_badges,0) * 5
        + coalesce(c.hot_q_count,0) * 20
        + coalesce(c.accepted_answers_given,0) * 15
        + coalesce(c.questions_asked,0)
        - coalesce(c.dup_marked_questions,0) * 3
        desc,
        c.user_id
    ) as tier_rank
  from composite c
  left join top_tag_pivot ttp on ttp.user_id = c.user_id
)
select
  r.user_id,
  r.displayname,
  r.location,
  r.websiteurl_norm as website,
  r.cohort_month,
  r.activity_tier,
  r.rep_bucket,
  r.tier_rank,
  r.recency_rank,
  r.reputation,
  r.current_rep,
  r.rough_activity_points,
  r.q_count,
  r.a_count,
  r.questions_asked,
  r.accepted_q_count,
  r.closed_q_count,
  r.accepted_answers_given,
  r.total_post_score,
  r.total_views,
  r.comment_count,
  r.comment_score_sum,
  round(r.comment_score_avg::numeric, 2) as comment_score_avg,
  r.upvotes_cast,
  r.downvotes_cast,
  r.bounties_touch,
  r.bounty_amount_sum,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.tag_badges,
  r.hot_q_count,
  r.removed_hot_q_count,
  r.dup_marked_questions,
  r.distinct_originals_referenced,
  r.edits_made,
  r.suggested_edits_applied,
  r.first_edit_at,
  r.last_edit_at,
  r.last_activity_at,
  r.top_tag_1,
  r.top_tag_2,
  r.top_tag_3,
  -- Complex predicate-driven label
  case
    when r.hot_q_count > 0 and r.accepted_answers_given > 10 then 'HotHelpful'
    when r.dup_marked_questions > 5 and r.accepted_q_count = 0 then 'StrugglingAsker'
    when r.edits_made > 50 and coalesce(r.comment_count,0) < 5 then 'SilentEditor'
    when r.bounty_amount_sum > 1000 then 'BountyWhale'
    else 'Generalist'
  end as persona_label
from ranked r
where
  -- complicated predicate with NULL logic and string ops
  (
    r.websiteurl_norm ilike '%github%' or
    (r.top_tag_1 is not null and r.top_tag_1 ~ '^(sql|postgres|mysql)$') or
    (r.location is not null and length(trim(r.location)) > 0 and position(',' in r.location) > 0)
  )
  and coalesce(r.last_activity_at, r.cohort_month) >= (date_trunc('month', now()) - interval '18 months')
  and (
    r.rep_bucket in ('Experienced','Veteran','Legend')
    or (r.activity_tier in ('Power','Active') and coalesce(r.total_post_score,0) >= 50)
  )
order by
  r.activity_tier asc,
  r.tier_rank asc
limit 500;