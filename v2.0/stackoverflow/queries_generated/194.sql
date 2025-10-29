-- {"query": "194.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2788} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    u.user_id,
    count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
    count(*) filter (where c.id is not null) as total_comments,
    sum(coalesce(p.score,0)) as sum_post_score,
    sum(coalesce(c.score,0)) as sum_comment_score,
    max(gold_badge_date) as latest_gold_badge_date,
    max(silver_badge_date) as latest_silver_badge_date,
    max(bronze_badge_date) as latest_bronze_badge_date
  from recent_users u
  left join posts p
    on p.owneruserid = u.user_id
   and p.creationdate >= u.creationdate
  left join comments c
    on c.userid = u.user_id
   and c.creationdate >= u.creationdate
  left join lateral (
    select
      max(case when b.class = 1 then b.date end) as gold_badge_date,
      max(case when b.class = 2 then b.date end) as silver_badge_date,
      max(case when b.class = 3 then b.date end) as bronze_badge_date
    from badges b
    where b.userid = u.user_id
  ) b on true
  group by u.user_id
),
question_metrics as (
  select
    q.owneruserid as user_id,
    count(*) as questions_asked,
    avg(nullif(q.viewcount,0)) as avg_question_views,
    avg(q.score) as avg_question_score,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_questions,
    sum(coalesce(q.answercount,0)) as total_answers_received,
    percentile_cont(0.9) within group (order by coalesce(q.viewcount,0)) as p90_views
  from posts q
  where q.posttypeid = 1
  group by q.owneruserid
),
answer_metrics as (
  select
    a.owneruserid as user_id,
    count(*) as answers_posted,
    avg(a.score) as avg_answer_score,
    sum(case when exists (
      select 1
      from posts q
      where q.id = a.parentid
        and q.acceptedanswerid = a.id
    ) then 1 else 0 end) as answers_accepted,
    sum(case when a.score >= 10 then 1 else 0 end) as high_score_answers
  from posts a
  where a.posttypeid = 2
  group by a.owneruserid
),
edit_events as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
    count(*) filter (where ph.posthistorytypeid in (10)) as closes_cast_old_schema,
    count(*) filter (where ph.posthistorytypeid in (11)) as reopens_cast_old_schema,
    count(*) filter (where ph.posthistorytypeid in (33,34)) as notices_touched
  from posthistory ph
  group by ph.userid
),
favorite_saves as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 5) as favorites_count
  from votes v
  group by v.userid
),
tag_engagement as (
  select
    u.user_id,
    array_agg(distinct tg.tagname order by tg.tagname) filter (where tg.tagname is not null) as top_tags,
    count(distinct tg.tagname) as distinct_tags_used
  from recent_users u
  left join posts p on p.owneruserid = u.user_id and p.posttypeid in (1,2)
  left join lateral (
    select unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
  ) t on p.posttypeid = 1 and p.tags is not null
  left join tags tg on tg.tagname = t.tagname
  group by u.user_id
),
postlink_graph as (
  select
    u.user_id,
    count(*) filter (where pl.linktypeid = 3) as duplicates_flagged,
    count(*) filter (where pl.linktypeid = 1) as linked_refs,
    max(pl.creationdate) as last_link_activity
  from recent_users u
  left join posts p on p.owneruserid = u.user_id
  left join postlinks pl on (pl.postid = p.id or pl.relatedpostid = p.id)
  group by u.user_id
),
activity_bins as (
  select
    u.user_id,
    case
      when coalesce(ua.total_posts,0) + coalesce(ua.total_comments,0) >= 1000 then 'whale'
      when coalesce(ua.total_posts,0) + coalesce(ua.total_comments,0) >= 200 then 'heavy'
      when coalesce(ua.total_posts,0) + coalesce(ua.total_comments,0) >= 50 then 'medium'
      when coalesce(ua.total_posts,0) + coalesce(ua.total_comments,0) >= 10 then 'light'
      else 'newbie'
    end as activity_tier
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
),
user_rank as (
  select
    u.user_id,
    dense_rank() over (order by coalesce(ua.sum_post_score,0) + coalesce(ua.sum_comment_score,0) desc, u.reputation desc) as score_rank,
    row_number() over (order by coalesce(am.answers_accepted,0) desc, coalesce(qm.accepted_questions,0) desc) as acceptance_rank
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join question_metrics qm on qm.user_id = u.user_id
  left join answer_metrics am on am.user_id = u.user_id
),
user_summary as (
  select
    u.user_id,
    u.displayname,
    u.location,
    u.websiteurl,
    u.reputation,
    ua.total_posts,
    ua.total_comments,
    ua.sum_post_score,
    ua.sum_comment_score,
    qm.questions_asked,
    qm.avg_question_views,
    qm.avg_question_score,
    qm.accepted_questions,
    qm.total_answers_received,
    qm.p90_views,
    am.answers_posted,
    am.avg_answer_score,
    am.answers_accepted,
    am.high_score_answers,
    ee.edits_made,
    ee.closes_cast_old_schema,
    ee.reopens_cast_old_schema,
    ee.notices_touched,
    fs.favorites_count,
    tg.top_tags,
    tg.distinct_tags_used,
    pg.duplicates_flagged,
    pg.linked_refs,
    pg.last_link_activity,
    ab.activity_tier,
    ur.score_rank,
    ur.acceptance_rank,
    greatest(coalesce(ua.latest_gold_badge_date, timestamp 'epoch'),
             coalesce(ua.latest_silver_badge_date, timestamp 'epoch'),
             coalesce(ua.latest_bronze_badge_date, timestamp 'epoch')) as latest_any_badge_date
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join question_metrics qm on qm.user_id = u.user_id
  left join answer_metrics am on am.user_id = u.user_id
  left join edit_events ee on ee.user_id = u.user_id
  left join favorite_saves fs on fs.user_id = u.user_id
  left join tag_engagement tg on tg.user_id = u.user_id
  left join postlink_graph pg on pg.user_id = u.user_id
  left join activity_bins ab on ab.user_id = u.user_id
  left join user_rank ur on ur.user_id = u.user_id
),
top_users as (
  select
    us.*,
    row_number() over (
      partition by us.activity_tier
      order by
        coalesce(us.sum_post_score,0) + coalesce(us.sum_comment_score,0) desc,
        coalesce(us.answers_accepted,0) desc,
        coalesce(us.questions_asked,0) desc,
        us.reputation desc,
        us.user_id desc
    ) as tier_rank
  from user_summary us
),
accepted_answer_latency as (
  select
    a.owneruserid as user_id,
    avg(extract(epoch from (q.lastactivitydate - a.creationdate)) / 3600.0) as avg_hours_to_last_activity_after_answer
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
  group by a.owneruserid
),
comment_sentiment_proxy as (
  select
    c.userid as user_id,
    avg(case when position('?' in coalesce(c.text,'')) > 0 then 1 else 0 end)::numeric as question_ratio,
    avg(case when position('thank' in lower(coalesce(c.text,''))) > 0 then 1 else 0 end)::numeric as thanks_ratio
  from comments c
  group by c.userid
)
select
  tu.user_id,
  tu.displayname,
  tu.location,
  tu.websiteurl,
  tu.reputation,
  tu.activity_tier,
  tu.tier_rank,
  tu.score_rank,
  tu.acceptance_rank,
  tu.total_posts,
  tu.total_comments,
  tu.sum_post_score,
  tu.sum_comment_score,
  tu.questions_asked,
  tu.avg_question_views,
  tu.avg_question_score,
  tu.accepted_questions,
  tu.total_answers_received,
  tu.p90_views,
  tu.answers_posted,
  tu.avg_answer_score,
  tu.answers_accepted,
  tu.high_score_answers,
  tu.edits_made,
  tu.closes_cast_old_schema,
  tu.reopens_cast_old_schema,
  tu.notices_touched,
  tu.favorites_count,
  tu.top_tags,
  tu.distinct_tags_used,
  tu.duplicates_flagged,
  tu.linked_refs,
  tu.last_link_activity,
  tu.latest_any_badge_date,
  coalesce(al.avg_hours_to_last_activity_after_answer, 0) as avg_hours_to_last_activity_after_answer,
  coalesce(sp.question_ratio, 0) as comment_question_ratio,
  coalesce(sp.thanks_ratio, 0) as comment_thanks_ratio
from top_users tu
left join accepted_answer_latency al on al.user_id = tu.user_id
left join comment_sentiment_proxy sp on sp.user_id = tu.user_id
where tu.tier_rank <= 25
union all
select
  us.user_id,
  us.displayname,
  us.location,
  us.websiteurl,
  us.reputation,
  us.activity_tier,
  null::bigint as tier_rank,
  us.score_rank,
  us.acceptance_rank,
  us.total_posts,
  us.total_comments,
  us.sum_post_score,
  us.sum_comment_score,
  us.questions_asked,
  us.avg_question_views,
  us.avg_question_score,
  us.accepted_questions,
  us.total_answers_received,
  us.p90_views,
  us.answers_posted,
  us.avg_answer_score,
  us.answers_accepted,
  us.high_score_answers,
  us.edits_made,
  us.closes_cast_old_schema,
  us.reopens_cast_old_schema,
  us.notices_touched,
  us.favorites_count,
  us.top_tags,
  us.distinct_tags_used,
  us.duplicates_flagged,
  us.linked_refs,
  us.last_link_activity,
  us.latest_any_badge_date,
  coalesce(al.avg_hours_to_last_activity_after_answer, 0) as avg_hours_to_last_activity_after_answer,
  coalesce(sp.question_ratio, 0) as comment_question_ratio,
  coalesce(sp.thanks_ratio, 0) as comment_thanks_ratio
from user_summary us
left join accepted_answer_latency al on al.user_id = us.user_id
left join comment_sentiment_proxy sp on sp.user_id = us.user_id
where us.user_id in (
  select user_id
  from user_summary
  where coalesce(sum_post_score,0) + coalesce(sum_comment_score,0) > (
    select avg(coalesce(sum_post_score,0) + coalesce(sum_comment_score,0)) from user_summary
  )
  and coalesce(answers_accepted,0) = 0
)
order by activity_tier, coalesce(tier_rank, 1e9), score_rank, acceptance_rank, user_id;