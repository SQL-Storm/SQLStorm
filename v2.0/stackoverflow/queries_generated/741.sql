-- {"query": "741.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3752} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.upvotes,
    u.downvotes,
    u.views,
    coalesce(nullif(trim(lower(u.location)), ''), 'unknown') as norm_location,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= now() - interval '5 years'
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(greatest(p.score, 0)) as positive_post_score,
    sum(least(p.score, 0)) as negative_post_score,
    avg(nullif(p.viewcount, 0)) as avg_viewcount_nonzero,
    count(*) filter (where p.closeddate is not null) as closed_count,
    count(distinct p.id) as total_posts,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
accepted_answers as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_count,
    sum(a.score) as accepted_score_sum
  from posts a
  join posts q on q.acceptedanswerid = a.id
  where a.posttypeid = 2
  group by a.owneruserid
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(c.score) as comment_score_sum,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
badges_by_class as (
  select
    b.userid as user_id,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
edits_and_events as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
    count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,31,33,34,35,36,37,38,50,52,53,66)) as moderation_events,
    max(ph.creationdate) as last_event_date
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
links_graph as (
  select
    p.owneruserid as user_id,
    count(distinct pl.relatedpostid) filter (where pl.linktypeid = 1) as linked_out_posts,
    count(distinct pl.postid) filter (where pl.linktypeid = 3) as duplicate_marks_as_source,
    count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as duplicate_targets
  from postlinks pl
  join posts p on p.id = pl.postid
  group by p.owneruserid
),
vote_breakdown as (
  select
    v.userid as voter_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 8) as bounties_started,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total_involved,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
question_quality as (
  select
    q.owneruserid as user_id,
    percentile_cont(0.5) within group (order by q.score) as median_q_score,
    avg(q.score) as avg_q_score,
    avg(q.viewcount) as avg_q_views,
    count(*) filter (where q.favoritecount is not null and q.favoritecount > 0) as faved_questions,
    count(*) filter (where q.answercount >= 1) as answered_questions
  from posts q
  where q.posttypeid = 1 and q.owneruserid is not null
  group by q.owneruserid
),
answer_quality as (
  select
    a.owneruserid as user_id,
    percentile_cont(0.5) within group (order by a.score) as median_a_score,
    avg(a.score) as avg_a_score,
    count(*) filter (where exists (
      select 1
      from posts q
      where q.acceptedanswerid = a.id
    )) as accepted_answers,
    count(*) filter (where a.score >= 5) as high_score_answers
  from posts a
  where a.posttypeid = 2 and a.owneruserid is not null
  group by a.owneruserid
),
user_cohorts as (
  select
    ru.user_id,
    ru.cohort_month,
    row_number() over (partition by ru.cohort_month order by ru.reputation desc, ru.user_id) as cohort_rank,
    count(*) over (partition by ru.cohort_month) as cohort_size
  from recent_users ru
),
-- detect users whose display names resemble emails or urls for string/regex stress
name_flags as (
  select
    u.id as user_id,
    case
      when u.displayname ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then 1 else 0
    end as looks_like_email,
    case
      when coalesce(u.websiteurl,'') ~* 'https?://' then 1 else 0
    end as has_http_url,
    length(coalesce(u.displayname,'')) as displayname_len
  from users u
),
-- activity recency bucketing using correlated subqueries
recency as (
  select
    u.id as user_id,
    least(
      coalesce(extract(epoch from (now() - (
        select max(ts) from (
          values
            ((select max(p.lastactivitydate) from posts p where p.owneruserid = u.id)),
            ((select max(c.creationdate) from comments c where c.userid = u.id)),
            ((select max(v.creationdate) from votes v where v.userid = u.id)),
            ((select max(b.date) from badges b where b.userid = u.id)),
            ((select max(ph.creationdate) from posthistory ph where ph.userid = u.id))
        ) as t(ts)
      )))::bigint, 3155760000), 3155760000
    ) as seconds_since_any_activity
  from users u
),
-- combine per-user aggregates
combined as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.views,
    ru.upvotes,
    ru.downvotes,
    ru.norm_location,
    uc.cohort_month,
    uc.cohort_rank,
    uc.cohort_size,
    ua.q_count,
    ua.a_count,
    ua.positive_post_score,
    ua.negative_post_score,
    ua.closed_count,
    ua.total_posts,
    ua.last_post_activity,
    coalesce(aacc.accepted_count, 0) as accepted_count,
    coalesce(aacc.accepted_score_sum, 0) as accepted_score_sum,
    coalesce(cs.comment_count, 0) as comment_count,
    coalesce(cs.comment_score_sum, 0) as comment_score_sum,
    coalesce(cs.positive_comments, 0) as positive_comments,
    cs.last_comment_date,
    coalesce(bc.gold_badges, 0) as gold_badges,
    coalesce(bc.silver_badges, 0) as silver_badges,
    coalesce(bc.bronze_badges, 0) as bronze_badges,
    coalesce(bc.tag_badges, 0) as tag_badges,
    bc.last_badge_date,
    coalesce(e.edit_events, 0) as edit_events,
    coalesce(e.moderation_events, 0) as moderation_events,
    e.last_event_date,
    coalesce(lg.linked_out_posts, 0) as linked_out_posts,
    coalesce(lg.duplicate_marks_as_source, 0) as duplicate_marks_as_source,
    coalesce(lg.duplicate_targets, 0) as duplicate_targets,
    coalesce(vb.upvotes_cast, 0) as upvotes_cast,
    coalesce(vb.downvotes_cast, 0) as downvotes_cast,
    coalesce(vb.bounties_started, 0) as bounties_started,
    coalesce(vb.bounty_total_involved, 0) as bounty_total_involved,
    vb.last_vote_date,
    qq.median_q_score,
    qq.avg_q_score,
    qq.avg_q_views,
    qq.faved_questions,
    qq.answered_questions,
    aq.median_a_score,
    aq.avg_a_score,
    aq.accepted_answers as accepted_answers_cnt,
    aq.high_score_answers,
    nf.looks_like_email,
    nf.has_http_url,
    nf.displayname_len,
    r.seconds_since_any_activity
  from recent_users ru
  left join user_cohorts uc on uc.user_id = ru.user_id
  left join user_activity ua on ua.user_id = ru.user_id
  left join accepted_answers aacc on aacc.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join badges_by_class bc on bc.user_id = ru.user_id
  left join edits_and_events e on e.user_id = ru.user_id
  left join links_graph lg on lg.user_id = ru.user_id
  left join vote_breakdown vb on vb.voter_id = ru.user_id
  left join question_quality qq on qq.user_id = ru.user_id
  left join answer_quality aq on aq.user_id = ru.user_id
  left join name_flags nf on nf.user_id = ru.user_id
  left join recency r on r.user_id = ru.user_id
),
-- create synthetic scoring and buckets
scored as (
  select
    c.*,
    -- penalize negative scores and downvotes, reward accepted answers, badges, and edits
    (
      0.50 * coalesce(c.reputation,0) +
      5.00 * coalesce(c.accepted_count,0) +
      3.00 * coalesce(c.gold_badges,0) +
      1.50 * coalesce(c.silver_badges,0) +
      0.50 * coalesce(c.bronze_badges,0) +
      0.25 * coalesce(c.edit_events,0) +
      0.10 * coalesce(c.moderation_events,0) +
      0.30 * coalesce(c.upvotes_cast,0) -
      0.80 * coalesce(c.downvotes_cast,0) +
      0.20 * coalesce(c.positive_post_score,0) +
      0.10 * abs(coalesce(c.negative_post_score,0)) * -1 +
      0.05 * coalesce(c.comment_score_sum,0) +
      0.02 * coalesce(c.linked_out_posts,0) +
      1.00 * coalesce(c.accepted_answers_cnt,0) +
      0.40 * coalesce(c.high_score_answers,0)
    ) as activity_score,
    case
      when c.seconds_since_any_activity < 86400 then 'active: <1d'
      when c.seconds_since_any_activity < 7*86400 then 'active: <1w'
      when c.seconds_since_any_activity < 30*86400 then 'active: <1m'
      when c.seconds_since_any_activity < 180*86400 then 'active: <6m'
      when c.seconds_since_any_activity < 365*86400 then 'active: <1y'
      else 'active: stale'
    end as recency_bucket,
    case
      when coalesce(c.q_count,0) + coalesce(c.a_count,0) >= 1000 then 'whale'
      when coalesce(c.q_count,0) + coalesce(c.a_count,0) >= 200 then 'power'
      when coalesce(c.q_count,0) + coalesce(c.a_count,0) >= 50 then 'regular'
      when coalesce(c.q_count,0) + coalesce(c.a_count,0) >= 10 then 'casual'
      when coalesce(c.q_count,0) + coalesce(c.a_count,0) >= 1 then 'newbie'
      else 'lurker'
    end as activity_tier
  from combined c
),
-- percentile ranks and dense ranks over score within cohorts and globally
ranked as (
  select
    s.*,
    percent_rank() over (order by s.activity_score) as global_score_prank,
    cume_dist() over (order by s.activity_score desc) as global_score_cdist_desc,
    dense_rank() over (order by s.activity_score desc) as global_score_rank_desc,
    percent_rank() over (partition by s.cohort_month order by s.activity_score) as cohort_score_prank,
    dense_rank() over (partition by s.cohort_month order by s.activity_score desc) as cohort_score_rank_desc
  from scored s
),
-- synthetic stress: join to tags via string matching on Tags array membership for user's questions
user_top_tags as (
  select
    p.owneruserid as user_id,
    t.tagname,
    count(*) as uses
  from posts p
  join lateral unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag(tagname) on true
  join tags t on lower(t.tagname) = lower(tag.tagname)
  where p.posttypeid = 1 and p.owneruserid is not null
  group by p.owneruserid, t.tagname
),
tag_rank as (
  select
    utt.user_id,
    utt.tagname,
    utt.uses,
    row_number() over (partition by utt.user_id order by utt.uses desc, utt.tagname) as rn
  from user_top_tags utt
),
top3_tags as (
  select
    tr.user_id,
    string_agg(tr.tagname || ' (' || tr.uses || ')', ', ' order by tr.rn) as top_tags
  from tr
  where tr.rn <= 3
  group by tr.user_id
)
select
  r.user_id,
  r.displayname,
  r.reputation,
  r.views,
  r.norm_location,
  r.cohort_month,
  r.cohort_rank,
  r.cohort_size,
  r.q_count,
  r.a_count,
  r.total_posts,
  r.accepted_count,
  r.accepted_answers_cnt,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.edit_events,
  r.moderation_events,
  r.duplicate_marks_as_source,
  r.duplicate_targets,
  r.upvotes_cast,
  r.downvotes_cast,
  r.avg_q_score,
  r.avg_a_score,
  r.median_q_score,
  r.median_a_score,
  r.activity_score,
  r.global_score_rank_desc,
  r.cohort_score_rank_desc,
  r.global_score_prank,
  r.cohort_score_prank,
  r.recency_bucket,
  r.activity_tier,
  coalesce(tt.top_tags, '(none)') as top_tags,
  -- demonstrate null logic and complex predicate output
  case
    when r.looks_like_email = 1 and (r.has_http_url = 1 or r.displayname_len < 3) then 'name: suspicious'
    when r.looks_like_email = 1 then 'name: email-like'
    when r.has_http_url = 1 then 'name: contains-url'
    else 'name: ok'
  end as name_health
from ranked r
left join top3_tags tt on tt.user_id = r.user_id
where
  -- complicated predicate mixing nulls and calculations
  (
    (coalesce(r.q_count,0) + coalesce(r.a_count,0) >= 5 and r.activity_score > 0)
    or (r.gold_badges >= 1 and r.avg_a_score is not null)
    or (r.recency_bucket in ('active: <1d', 'active: <1w') and r.total_posts is not null)
  )
  and not (
    r.norm_location ilike '%test%'
    and coalesce(r.duplicate_targets,0) = 0
    and (r.comment_count is null or r.comment_count = 0)
  )
order by
  r.activity_score desc nulls last,
  r.accepted_answers_cnt desc nulls last,
  r.reputation desc nulls last
limit 500;