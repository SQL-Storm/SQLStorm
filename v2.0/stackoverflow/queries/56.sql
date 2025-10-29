-- {"query": "56.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2890} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'https://example.invalid/' || replace(lower(coalesce(u.displayname, 'anon')), ' ', '-')) as normalized_site,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_badge_rollup as (
  select
    b.userid,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_activity as (
  select
    p.owneruserid as user_id,
    count(*) as questions,
    count(*) filter (where p.acceptedanswerid is not null) as accepted_questions,
    sum(coalesce(p.viewcount, 0)) as total_views,
    avg(nullif(p.score, 0)) as avg_nonzero_score,
    percentile_disc(0.9) within group (order by coalesce(p.viewcount, 0)) as p90_views,
    max(p.creationdate) as last_question_date
  from posts p
  where p.posttypeid = 1
  group by p.owneruserid
),
answer_activity as (
  select
    p.owneruserid as user_id,
    count(*) as answers,
    sum(case when p.id in (select acceptedanswerid from posts where acceptedanswerid is not null) then 1 else 0 end) as accepted_answers,
    avg(p.score) as avg_answer_score,
    sum(case when p.score > 0 then 1 else 0 end) as positive_answers,
    max(p.creationdate) as last_answer_date
  from posts p
  where p.posttypeid = 2
  group by p.owneruserid
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comments,
    avg(c.score) as avg_comment_score,
    max(c.creationdate) as last_comment_date,
    count(*) filter (where position('thanks' in lower(c.text)) > 0 or position('thank you' in lower(c.text)) > 0) as polite_comments
  from comments c
  group by c.userid
),
post_link_dupes as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  group by pl.postid
),
closure_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_close_date,
    count(*) as close_votes_events,
    sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_events_only,
    count(distinct ph.userid) filter (where ph.posthistorytypeid in (10,11)) as distinct_close_reopen_users
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
user_post_rollup as (
  select
    p.owneruserid as user_id,
    count(*) as total_posts,
    sum(coalesce(p.commentcount,0)) as total_post_comments,
    sum(case when p.closeddate is not null then 1 else 0 end) as closed_posts,
    sum(coalesce(pld.duplicate_links,0)) as total_duplicate_links,
    sum(coalesce(pld.related_links,0)) as total_related_links,
    sum(case when ce.first_close_date is not null then 1 else 0 end) as posts_ever_closed_or_reopened
  from posts p
  left join post_link_dupes pld on pld.postid = p.id
  left join closure_events ce on ce.postid = p.id
  group by p.owneruserid
),
votes_rollup as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
    sum(coalesce(v.bountyamount,0)) as bounty_amount_total,
    max(v.creationdate) as last_vote_date
  from votes v
  group by v.userid
),
tag_derived as (
  select
    t.tagname,
    t.count as tag_post_count,
    t.ismoderatoronly,
    t.isrequired,
    coalesce(ep.owneruserid, wp.owneruserid, -1) as maintainer_user_id
  from tags t
  left join posts ep on ep.id = t.excerptpostid
  left join posts wp on wp.id = t.wikipostid
),
user_tag_influence as (
  select
    maintainer_user_id as user_id,
    count(*) as maintained_tags,
    sum(tag_post_count) as maintained_tag_posts,
    sum(case when ismoderatoronly then 1 else 0 end) as mod_only_tags,
    sum(case when isrequired then 1 else 0 end) as required_tags
  from tag_derived
  where maintainer_user_id is not null and maintainer_user_id <> -1
  group by maintainer_user_id
),
active_recent_users as (
  select ru.*
  from recent_users ru
  where ru.rn <= 5000
),
user_activity_union as (
  select user_id from question_activity
  union
  select user_id from answer_activity
  union
  select user_id from comment_stats
  union
  select user_id from user_post_rollup
  union
  select user_id from votes_rollup
  union
  select user_id from user_tag_influence
),
ranked_power_users as (
  select
    uar.user_id,
    coalesce(qa.questions, 0) as questions,
    coalesce(aa.answers, 0) as answers,
    coalesce(cs.comments, 0) as comments,
    coalesce(qa.total_views, 0) as total_views,
    coalesce(aa.avg_answer_score, 0) as avg_answer_score,
    coalesce(vr.upvotes_cast, 0) as upvotes_cast,
    coalesce(vr.downvotes_cast, 0) as downvotes_cast,
    coalesce(vr.bounty_amount_total, 0) as bounty_total,
    coalesce(upr.total_posts, 0) as total_posts
  from user_activity_union uar
  left join question_activity qa on qa.user_id = uar.user_id
  left join answer_activity aa on aa.user_id = uar.user_id
  left join comment_stats cs on cs.user_id = uar.user_id
  left join votes_rollup vr on vr.user_id = uar.user_id
  left join user_post_rollup upr on upr.user_id = uar.user_id
),
scored_users as (
  select
    rpu.user_id,
    0.30 * ln(1 + rpu.answers) +
    0.20 * ln(1 + rpu.questions) +
    0.10 * ln(1 + rpu.comments) +
    0.20 * ln(1 + rpu.total_views) / nullif(ln(10),0) +
    0.10 * greatest(rpu.avg_answer_score, 0) -
    0.15 * ln(1 + rpu.downvotes_cast) +
    0.05 * ln(1 + rpu.upvotes_cast) +
    0.05 * ln(1 + rpu.bounty_total) as activity_score
  from ranked_power_users rpu
),
final_agg as (
  select
    aru.user_id,
    aru.displayname,
    aru.reputation,
    aru.creationdate,
    aru.location,
    aru.normalized_site,
    coalesce(ubr.gold_badges,0) as gold_badges,
    coalesce(ubr.silver_badges,0) as silver_badges,
    coalesce(ubr.bronze_badges,0) as bronze_badges,
    coalesce(qa.questions,0) as questions,
    coalesce(qa.accepted_questions,0) as accepted_questions,
    coalesce(qa.total_views,0) as total_question_views,
    coalesce(qa.avg_nonzero_score,0) as avg_question_nonzero_score,
    qa.p90_views as p90_question_views,
    coalesce(aa.answers,0) as answers,
    coalesce(aa.accepted_answers,0) as accepted_answers,
    coalesce(aa.avg_answer_score,0) as avg_answer_score,
    coalesce(aa.positive_answers,0) as positive_answers,
    coalesce(cs.comments,0) as comments,
    coalesce(cs.avg_comment_score,0) as avg_comment_score,
    coalesce(cs.polite_comments,0) as polite_comments,
    coalesce(upr.total_posts,0) as total_posts,
    coalesce(upr.total_post_comments,0) as total_post_comments,
    coalesce(upr.closed_posts,0) as closed_posts,
    coalesce(upr.total_duplicate_links,0) as duplicate_links,
    coalesce(upr.total_related_links,0) as related_links,
    coalesce(uti.maintained_tags,0) as maintained_tags,
    coalesce(uti.maintained_tag_posts,0) as maintained_tag_posts,
    coalesce(uti.mod_only_tags,0) as mod_only_tags,
    coalesce(uti.required_tags,0) as required_tags,
    coalesce(vr.upvotes_cast,0) as upvotes_cast,
    coalesce(vr.downvotes_cast,0) as downvotes_cast,
    coalesce(vr.favorites_cast,0) as favorites_cast,
    coalesce(vr.bounty_events,0) as bounty_events,
    coalesce(vr.bounty_amount_total,0) as bounty_amount_total,
    greatest(coalesce(qa.last_question_date, timestamp 'epoch'),
             coalesce(aa.last_answer_date, timestamp 'epoch'),
             coalesce(cs.last_comment_date, timestamp 'epoch'),
             coalesce(vr.last_vote_date, timestamp 'epoch')) as last_activity_date,
    su.activity_score,
    row_number() over (order by su.activity_score desc, aru.reputation desc, aru.user_id) as activity_rank
  from active_recent_users aru
  left join user_badge_rollup ubr on ubr.userid = aru.user_id
  left join question_activity qa on qa.user_id = aru.user_id
  left join answer_activity aa on aa.user_id = aru.user_id
  left join comment_stats cs on cs.user_id = aru.user_id
  left join user_post_rollup upr on upr.user_id = aru.user_id
  left join votes_rollup vr on vr.user_id = aru.user_id
  left join user_tag_influence uti on uti.user_id = aru.user_id
  left join scored_users su on su.user_id = aru.user_id
),
null_safety as (
  select
    fa.*,
    case
      when fa.accepted_answers > fa.answers then fa.answers
      else fa.accepted_answers
    end as accepted_answers_capped,
    case
      when fa.accepted_questions > fa.questions then fa.questions
      else fa.accepted_questions
    end as accepted_questions_capped
  from final_agg fa
),
dense_buckets as (
  select
    ns.*,
    ntile(20) over (order by activity_score desc nulls last) as score_bucket,
    sum(total_posts) over (order by activity_rank rows between unbounded preceding and current row) as running_total_posts
  from null_safety ns
)
select
  db.user_id,
  db.displayname,
  db.reputation,
  db.location,
  db.normalized_site,
  db.activity_rank,
  db.score_bucket,
  db.activity_score,
  db.questions,
  db.accepted_questions_capped as accepted_questions,
  db.answers,
  db.accepted_answers_capped as accepted_answers,
  db.comments,
  db.total_posts,
  db.total_post_comments,
  db.closed_posts,
  db.duplicate_links,
  db.related_links,
  db.gold_badges,
  db.silver_badges,
  db.bronze_badges,
  db.maintained_tags,
  db.maintained_tag_posts,
  db.mod_only_tags,
  db.required_tags,
  db.upvotes_cast,
  db.downvotes_cast,
  db.favorites_cast,
  db.bounty_events,
  db.bounty_amount_total,
  db.last_activity_date,
  db.p90_question_views,
  db.avg_answer_score,
  db.avg_comment_score,
  db.polite_comments,
  db.running_total_posts
from dense_buckets db
where
  (db.answers + db.questions + db.comments) > 0
  and (
    db.activity_score > (
      select avg(activity_score)
      from final_agg
      where activity_score is not null
    )
    or db.gold_badges >= 1
  )
order by db.activity_rank
limit 500;