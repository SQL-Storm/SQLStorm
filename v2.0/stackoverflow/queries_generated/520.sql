-- {"query": "520.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2899} 
with recent_active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b
    on b.userid = u.id
  where u.lastaccessdate > now() - interval '365 days'
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.location, u.websiteurl
  having coalesce(count(b.id), 0) >= 0
),
question_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as questions,
    sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
    sum(coalesce(p.score,0)) filter (where p.posttypeid = 1) as question_score,
    count(*) filter (where p.posttypeid = 2) as answers,
    sum(coalesce(p.score,0)) filter (where p.posttypeid = 2) as answer_score,
    count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as accepted_questions,
    count(*) filter (where p.posttypeid = 1 and p.closuredate is not null) as closed_questions,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comments,
    sum(coalesce(c.score,0)) as comment_score,
    max(c.creationdate) as last_comment_date,
    avg(length(c.text))::numeric(18,2) as avg_comment_len
  from comments c
  where c.userid is not null
  group by c.userid
),
post_quality as (
  select
    p.owneruserid as user_id,
    percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_post_score,
    avg(coalesce(p.score,0)) as avg_post_score,
    stddev_pop(coalesce(p.score,0)) as std_post_score,
    min(coalesce(p.score,0)) as min_post_score,
    max(coalesce(p.score,0)) as max_post_score
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
tag_expertise as (
  select
    q.owneruserid as user_id,
    lower(trim(tg)) as tagname,
    count(*) as tag_posts,
    sum(coalesce(q.score,0)) as tag_score
  from posts q
  cross join lateral (
    select unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><'))
  ) as tag_laterals(tg)
  where q.posttypeid = 1 and q.tags is not null and q.owneruserid is not null
  group by q.owneruserid, lower(trim(tg))
),
top_tag_per_user as (
  select distinct on (te.user_id)
    te.user_id,
    te.tagname,
    te.tag_posts,
    te.tag_score
  from tag_expertise te
  order by te.user_id, te.tag_score desc, te.tag_posts desc, te.tagname
),
vote_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid = 8) as bounties_started,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
  from votes v
  where v.userid is not null
  group by v.userid
),
dupe_links as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.creationdate as dupe_link_date
  from postlinks pl
  where pl.linktypeid = 3
),
closure_reasons as (
  select
    ph.postid,
    max(ph.creationdate) as last_close_date,
    max(
      case
        when ph.posthistorytypeid = 10 then
          nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '')
        else null
      end
    ) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
question_health as (
  select
    q.owneruserid as user_id,
    count(*) filter (where q.posttypeid = 1) as total_questions,
    count(*) filter (where q.posttypeid = 1 and q.acceptedanswerid is not null) as accepted_q,
    avg(case when q.posttypeid = 1 then coalesce(q.viewcount,0) end) as avg_views_q,
    sum(case when q.posttypeid = 1 and exists (
      select 1 from dupe_links d where d.postid = q.id
    ) then 1 else 0 end) as duplicate_flags,
    sum(case when q.posttypeid = 1 and exists (
      select 1 from closure_reasons cr where cr.postid = q.id and cr.last_close_date is not null
    ) then 1 else 0 end) as closed_flags
  from posts q
  where q.owneruserid is not null
  group by q.owneruserid
),
user_activity_rank as (
  select
    rau.user_id,
    row_number() over (order by coalesce(qa.questions,0) + coalesce(qa.answers,0) desc, coalesce(qa.question_score,0) + coalesce(qa.answer_score,0) desc) as activity_rank,
    dense_rank() over (order by coalesce(qa.answer_score,0) desc) as answer_score_rank,
    ntile(10) over (order by coalesce(qa.question_views,0) desc) as view_ntile
  from recent_active_users rau
  left join question_activity qa on qa.user_id = rau.user_id
),
suspicious_accounts as (
  select
    u.id as user_id,
    case
      when u.upvotes + u.downvotes = 0 then null
      else (u.upvotes::numeric / nullif(u.upvotes + u.downvotes,0))::numeric(6,4)
    end as upvote_ratio_profile,
    case
      when coalesce(cs.comments,0) > 0 and coalesce(qa.answers,0) = 0 and coalesce(qa.questions,0) = 0 then 1
      else 0
    end as comment_only_flag,
    case
      when u.reputation < 50 and coalesce(qa.questions,0) >= 10 and coalesce(qa.answer_score,0) <= 0 then 1
      else 0
    end as low_rep_many_questions_flag
  from users u
  left join question_activity qa on qa.user_id = u.id
  left join comment_stats cs on cs.user_id = u.id
),
user_summary as (
  select
    rau.user_id,
    rau.displayname,
    rau.reputation,
    rau.creationdate,
    rau.lastaccessdate,
    rau.location,
    rau.websiteurl,
    rau.gold_badges,
    rau.silver_badges,
    rau.bronze_badges,
    rau.last_badge_date,
    qa.questions,
    qa.answers,
    qa.question_score,
    qa.answer_score,
    qa.question_views,
    qa.accepted_questions,
    qa.closed_questions,
    qa.last_post_activity,
    cs.comments,
    cs.comment_score,
    cs.last_comment_date,
    cs.avg_comment_len,
    pq.median_post_score,
    pq.avg_post_score,
    pq.std_post_score,
    pq.min_post_score,
    pq.max_post_score,
    coalesce(v.upvotes_cast,0) as upvotes_cast,
    coalesce(v.downvotes_cast,0) as downvotes_cast,
    coalesce(v.favorites_cast,0) as favorites_cast,
    coalesce(v.bounties_started,0) as bounties_started,
    coalesce(v.bounty_amount_total,0) as bounty_amount_total,
    coalesce(tt.tagname, '(none)') as top_tag,
    coalesce(tt.tag_posts,0) as top_tag_posts,
    coalesce(tt.tag_score,0) as top_tag_score,
    uh.total_questions,
    uh.accepted_q,
    uh.avg_views_q,
    uh.duplicate_flags,
    uh.closed_flags
  from recent_active_users rau
  left join question_activity qa on qa.user_id = rau.user_id
  left join comment_stats cs on cs.user_id = rau.user_id
  left join post_quality pq on pq.user_id = rau.user_id
  left join vote_agg v on v.user_id = rau.user_id
  left join top_tag_per_user tt on tt.user_id = rau.user_id
  left join question_health uh on uh.user_id = rau.user_id
),
bench as (
  select
    us.*,
    uar.activity_rank,
    uar.answer_score_rank,
    uar.view_ntile,
    sa.upvote_ratio_profile,
    sa.comment_only_flag,
    sa.low_rep_many_questions_flag,
    case
      when coalesce(us.answers,0) = 0 then null
      else (coalesce(us.accepted_q,0)::numeric / nullif(us.total_questions,0))::numeric(6,4)
    end as question_accept_rate,
    case
      when coalesce(us.answers,0) = 0 then null
      else (coalesce(us.answer_score,0)::numeric / nullif(us.answers,0))::numeric(12,4)
    end as avg_answer_score_per_answer,
    case
      when coalesce(us.questions,0) = 0 then null
      else (coalesce(us.question_views,0)::numeric / nullif(us.questions,0))::numeric(18,2)
    end as avg_views_per_question,
    case
      when coalesce(us.gold_badges,0) + coalesce(us.silver_badges,0) + coalesce(us.bronze_badges,0) = 0 then 0
      else 1
    end as has_any_badge_flag,
    greatest(
      coalesce(us.avg_post_score, -100000),
      coalesce(us.median_post_score, -100000)
    ) as conservative_quality_metric
  from user_summary us
  left join user_activity_rank uar on uar.user_id = us.user_id
  left join suspicious_accounts sa on sa.user_id = us.user_id
)
select
  b.user_id,
  b.displayname,
  b.reputation,
  b.location,
  b.websiteurl,
  b.activity_rank,
  b.answer_score_rank,
  b.view_ntile,
  b.questions,
  b.answers,
  b.question_score,
  b.answer_score,
  b.comments,
  b.comment_score,
  b.upvotes_cast,
  b.downvotes_cast,
  b.bounties_started,
  b.bounty_amount_total,
  b.top_tag,
  b.top_tag_posts,
  b.top_tag_score,
  b.total_questions,
  b.accepted_q,
  b.avg_views_q,
  b.duplicate_flags,
  b.closed_flags,
  b.question_accept_rate,
  b.avg_answer_score_per_answer,
  b.avg_views_per_question,
  b.has_any_badge_flag,
  b.conservative_quality_metric,
  b.median_post_score,
  b.avg_post_score,
  b.std_post_score,
  b.min_post_score,
  b.max_post_score,
  b.last_post_activity,
  b.last_comment_date,
  b.last_badge_date,
  b.creationdate,
  b.lastaccessdate,
  b.comment_only_flag,
  b.low_rep_many_questions_flag,
  coalesce(b.upvote_ratio_profile, 0) as upvote_ratio_profile,
  case
    when b.downvotes_cast > b.upvotes_cast then 'more-downvotes-cast'
    when b.upvotes_cast > b.downvotes_cast then 'more-upvotes-cast'
    else 'balanced'
  end as vote_cast_balance_bucket
from bench b
where
  (
    coalesce(b.answers,0) > 0
    or coalesce(b.questions,0) > 0
    or coalesce(b.comments,0) > 10
  )
  and (
    b.reputation >= 100
    or b.has_any_badge_flag = 1
    or b.avg_post_score > 1
  )
  and (
    b.top_tag is null
    or b.top_tag not in ('discussion', 'homework')
    or b.top_tag like '%sql%'
  )
order by
  b.conservative_quality_metric desc nulls last,
  b.avg_views_per_question desc nulls last,
  b.activity_rank asc nulls last
limit 250;