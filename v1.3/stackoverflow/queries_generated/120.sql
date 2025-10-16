-- {"query": "120.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2562} 
with recent_posts as (
  select p.*
  from posts p
  where p.creationdate >= now() - interval '365 days'
),
exploded_tags as (
  select
    p.id as post_id,
    lower(trim(t)) as tag
  from recent_posts p
  cross join lateral (
    select regexp_split_to_table(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,'')) - 2,0)), '><') as t
  ) s
  where p.posttypeid = 1 and coalesce(p.tags,'') <> ''
),
tag_stats as (
  select
    tag,
    count(distinct post_id) as question_count,
    sum((select count(*) from posts a where a.parentid = q.id)) as derived_answer_sum -- correlated inside aggregate intentionally expensive
  from exploded_tags et
  join posts q on q.id = et.post_id
  group by tag
),
user_posts as (
  -- union of questions and answers with some additional computed columns; then exclude community placeholder (-1)
  select u.id as userid, p.id as postid, p.posttypeid, p.parentid, p.score, p.viewcount,
         p.creationdate, p.title, p.tags,
         case when p.posttypeid = 1 then array_length(regexp_split_to_array(substring(coalesce(p.tags,''),2, greatest(length(coalesce(p.tags,'')) - 2,0)), '><'),1) else null end as tag_count,
         (select count(*) from comments c where c.postid = p.id) as comment_count,
         (select max(v.creationdate) from votes v where v.postid = p.id) as last_vote_date
  from posts p
  left join users u on u.id = p.owneruserid
  where coalesce(p.owneruserid,-1) > 0
),
badge_summary as (
  select b.userid,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(*) as total_badges,
         bool_or(b.tagbased) as has_tag_badges
  from badges b
  group by b.userid
),
vote_aggregates as (
  select p.owneruserid as userid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_received
  from votes v
  join posts p on p.id = v.postid
  where p.owneruserid is not null
  group by p.owneruserid
),
user_activity_windows as (
  select
    up.userid,
    count(*) filter (where up.posttypeid = 1) as questions_count,
    count(*) filter (where up.posttypeid = 2) as answers_count,
    avg(up.score) over (partition by up.userid) as avg_post_score,
    max(up.creationdate) over (partition by up.userid) as last_post_date,
    row_number() over (partition by up.userid order by up.creationdate desc) as rn_latest_by_user,
    sum(up.comment_count) over (partition by up.userid) as total_comments_on_posts
  from user_posts up
),
latest_user_posts as (
  select distinct on (userid) userid, postid as latest_postid, creationdate as latest_post_date, title
  from user_posts
  order by userid, creationdate desc
),
answer_quality as (
  -- correlated subquery to compute for each answer whether it beat its siblings by score and by being accepted
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid,
         a.score,
         case
           when a.id = q.acceptedanswerid then 1
           when a.score = (select max(s.score) from posts s where s.parentid = a.parentid) then 1
           else 0
         end as is_top_answer_or_accepted,
         (select count(*) from comments c where c.postid = a.id and c.creationdate >= now() - interval '30 days') as recent_comments_30d
  from posts a
  join posts q on q.id = a.parentid
  where a.posttypeid = 2
),
user_answer_stats as (
  select
    aq.owneruserid as userid,
    count(*) as answers_given,
    sum(aq.score) as total_answer_score,
    sum(aq.is_top_answer_or_accepted) as top_or_accepted_count,
    avg(aq.score) as avg_answer_score,
    max(aq.recent_comments_30d) as max_recent_comments_on_an_answer
  from answer_quality aq
  group by aq.owneruserid
),
user_summary as (
  select u.id as userid,
         u.displayname,
         u.reputation,
         u.creationdate as user_creation,
         u.lastaccessdate,
         coalesce(bs.gold_badges,0) as gold_badges,
         coalesce(bs.silver_badges,0) as silver_badges,
         coalesce(bs.bronze_badges,0) as bronze_badges,
         coalesce(va.upvotes_received,0) as upvotes_received,
         coalesce(va.downvotes_received,0) as downvotes_received,
         coalesce(us.questions_count,0) as questions_count,
         coalesce(us.answers_count,0) as answers_count,
         coalesce(uas.answers_given,0) as answers_given,
         coalesce(uas.total_answer_score,0) as total_answer_score,
         coalesce(us.avg_post_score,0) as avg_post_score,
         coalesce(us.last_post_date, u.lastaccessdate) as last_activity,
         least(coalesce(u.views,0), 2147483647)::bigint as views_clamped,
         case when (coalesce(bs.total_badges,0) = 0 and coalesce(va.upvotes_received,0) > 50) then 'lurker_with_votes'
              when coalesce(uas.answers_given,0) > coalesce(us.questions_count,0) then 'answerer'
              when coalesce(us.questions_count,0) >= coalesce(uas.answers_given,0) and coalesce(us.questions_count,0) > 0 then 'questioner'
              else 'casual'
         end as user_type
  from users u
  left join badge_summary bs on bs.userid = u.id
  left join vote_aggregates va on va.userid = u.id
  left join user_activity_windows us on us.userid = u.id
  left join user_answer_stats uas on uas.userid = u.id
),
top_tags_union as (
  -- expensive set operator: union of tag_stats filtered differently, then except some trivial tags
  select tag, question_count from tag_stats where question_count > 5
  union
  select tag, question_count from tag_stats where tag ~ '^[a-z0-9\-_]+$' and question_count > 1
  except
  select tag, question_count from tag_stats where tag in ('homework','beginner')
),
heavy_users as (
  select userid
  from user_summary
  where (questions_count + answers_count) >= 50
     or reputation >= 10000
     or gold_badges >= 3
),
final_ranking as (
  select
    us.userid,
    us.displayname,
    us.reputation,
    us.user_type,
    us.questions_count,
    us.answers_count,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.upvotes_received,
    us.downvotes_received,
    us.views_clamped,
    coalesce(uas.avg_answer_score,0) as avg_answer_score,
    us.last_activity,
    dense_rank() over (order by (us.reputation*0.6 + coalesce(uas.total_answer_score,0)*0.3 + coalesce(us.answers_count,0)*0.1) desc) as influence_rank,
    row_number() over (partition by us.user_type order by us.reputation desc) as rank_within_type,
    (select count(*) from posts p where p.owneruserid = us.userid and p.creationdate >= now() - interval '30 days') as posts_last_30d,
    exists (select 1 from posts q where q.owneruserid = us.userid and q.posttypeid = 1 and q.acceptedanswerid is not null) as has_questions_with_accepted_answers,
    (select string_agg(distinct lower(trim(t)), ',') from exploded_tags et join posts p on p.id = et.post_id where p.owneruserid = us.userid limit 10) as common_tags
  from user_summary us
  left join user_answer_stats uas on uas.userid = us.userid
  where us.userid in (select userid from heavy_users)
)
select
  fr.*,
  ts.tag as representative_tag,
  ts.question_count as tag_question_count,
  -- tense string expression and null logic examples
  case
    when fr.posts_last_30d is null then 'no recent posts'
    when fr.posts_last_30d = 0 then 'inactive-month'
    when fr.posts_last_30d > 10 then 'very-active'
    else concat('active-', fr.posts_last_30d::text)
  end as recent_activity_label,
  -- correlated scalar subquery to pick the latest comment text on the latest post (expensive)
  (select c.text from comments c
   join posts p on p.id = c.postid
   where p.owneruserid = fr.userid
   order by c.creationdate desc
   limit 1) as latest_comment_on_user_post,
  -- include a flag if user has ever been the owner of an accepted answer in the last year (correlated)
  (select count(*) > 0 from posts a join posts q on q.id = a.parentid where a.owneruserid = fr.userid and a.creationdate >= now() - interval '365 days' and q.acceptedanswerid = a.id) as accepted_in_last_year,
  -- window over tag stats to compute percentile (join heavy representative tag via left join)
  ntile(10) over (order by coalesce(ts.question_count,0) desc) as tag_popularity_decile
from final_ranking fr
left join lateral (
  select tag, question_count
  from top_tags_union ttu
  where ttu.tag = (select (regexp_split_to_table(coalesce(fr.common_tags,''),',')) limit 1) -- attempt to match one common tag
  limit 1
) ts on true
order by fr.influence_rank, fr.reputation desc
limit 250;