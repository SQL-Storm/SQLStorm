with recent_questions as (
  select p.id,
         p.title,
         p.creationdate,
         p.owneruserid,
         coalesce(p.viewcount, 0) as views,
         coalesce(p.score, 0) as score,
         coalesce(p.answercount, 0) as answer_count,
         substring(coalesce(p.tags, ''), 2, greatest(length(coalesce(p.tags, '')) - 2, 0)) as raw_tags,
         regexp_split_to_table(substring(coalesce(p.tags, ''), 2, greatest(length(coalesce(p.tags, '')) - 2, 0)), '><') as single_tag
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
user_stats as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate as user_since,
         coalesce(u.views, 0) as profile_views,
         coalesce(u.upvotes, 0) as up_votes,
         coalesce(u.downvotes, 0) as down_votes,
         (select count(*) from posts p where p.owneruserid = u.id and p.posttypeid = 1) as questions_posted,
         (select count(*) from posts p where p.owneruserid = u.id and p.posttypeid = 2) as answers_posted,
         (select count(*) from badges b where b.userid = u.id) as badges_total,
         (select count(*) from badges b where b.userid = u.id and b.class = 1) as gold_badges,
         (select count(*) from votes v where v.userid = u.id and v.votetypeid = 5) as favorites_given
  from users u
  where u.creationdate <= cast('2024-10-01 12:34:56' as timestamp)
),
tag_aggregates as (
  select rq.single_tag as tag,
         count(distinct rq.id) as q_count,
         sum(rq.views) as total_views,
         avg(rq.score) as avg_score,
         max(rq.answer_count) as max_answers,
         count(distinct rq.owneruserid) as unique_askers
  from recent_questions rq
  group by rq.single_tag
),
top_tag_users as (
  select t.tagname as tag,
         u.id as user_id,
         u.displayname,
         count(p.id) as posts_in_tag,
         sum(coalesce(p.score, 0)) as score_sum,
         row_number() over (partition by t.tagname order by count(p.id) desc, sum(coalesce(p.score, 0)) desc) as rn
  from tags t
  join recent_questions rq on rq.single_tag = t.tagname
  join posts p on p.owneruserid = rq.owneruserid and p.posttypeid in (1, 2)
  join users u on u.id = p.owneruserid
  group by t.tagname, u.id, u.displayname
),
top_tags_limited as (
  select tag, q_count, total_views, avg_score, max_answers, unique_askers
  from tag_aggregates
  where q_count >= 10
  order by q_count desc
  limit 50
),
answers_with_penalty as (
  select a.id,
         a.parentid as question_id,
         a.owneruserid,
         a.creationdate,
         a.score,
         a.body,
         length(a.body) as body_len,
         power(abs(coalesce(a.score, 0)) + 1, 0.75) * ln(1 + greatest(length(a.body), 1)) as score_penalty,
         (select count(*) from comments c where c.postid = a.id) as comment_count
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
question_metrics as (
  select q.id,
         q.title,
         q.creationdate,
         q.owneruserid,
         q.viewcount,
         q.score,
         q.answercount,
         q.tags,
         (select count(*) from comments c where c.postid = q.id) as comment_count,
         coalesce((select sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) from votes v where v.postid = q.id), 0) as vote_balance,
         (select count(*) from postlinks pl where pl.postid = q.id and pl.linktypeid = 3) as duplicate_links,
         (select max(ph.creationdate) from posthistory ph where ph.postid = q.id) as last_revision,
         tag_items.tag_array
  from posts q
  left join lateral (
    select array_agg(t) as tag_array
    from (
      select distinct regexp_split_to_table(substring(coalesce(q.tags, ''), 2, greatest(length(coalesce(q.tags, '')) - 2, 0)), '><') as t
    ) s
  ) tag_items on true
  where q.posttypeid = 1
    and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
combined as (
  select qt.id as question_id,
         qt.title,
         qt.creationdate as question_created,
         qt.owneruserid,
         us.displayname as asker_name,
         coalesce(qt.viewcount, 0) as q_views,
         coalesce(qt.score, 0) as q_score,
         coalesce(qt.answercount, 0) as q_answers,
         qt.tag_array,
         ta.q_count,
         ta.total_views as tag_total_views,
         ta.avg_score as tag_avg_score,
         atp.user_id as top_contributor_id,
         atp.displayname as top_contributor_name,
         atp.posts_in_tag,
         coalesce(sum(awp.score_penalty) filter (where awp.question_id = qt.id), 0) as sum_answer_penalties,
         coalesce(max(awp.score) filter (where awp.question_id = qt.id), 0) as top_answer_score,
         coalesce(min(awp.body_len) filter (where awp.question_id = qt.id), 0) as shortest_answer_len,
         qt.comment_count,
         qt.vote_balance,
         qt.duplicate_links,
         qt.last_revision
  from question_metrics qt
  left join recent_questions rq on rq.id = qt.id
  left join lateral (
    select ta.tag, ta.q_count, ta.total_views, ta.avg_score
    from tag_aggregates ta
    join lateral (
      select regexp_split_to_table(substring(coalesce(qt.tags, ''), 2, greatest(length(coalesce(qt.tags, '')) - 2, 0)), '><') as t
    ) tt on ta.tag = tt.t
    limit 1
  ) ta on true
  left join lateral (
    select ttu.tag, ttu.user_id, ttu.displayname, ttu.posts_in_tag
    from top_tag_users ttu
    join lateral (
      select regexp_split_to_table(substring(coalesce(qt.tags, ''), 2, greatest(length(coalesce(qt.tags, '')) - 2, 0)), '><') as t
    ) tt on ttu.tag = tt.t
    order by ttu.posts_in_tag desc
    limit 1
  ) atp on true
  left join users us on us.id = qt.owneruserid
  left join answers_with_penalty awp on awp.question_id = qt.id
  group by qt.id, qt.title, qt.creationdate, qt.owneruserid, us.displayname, qt.viewcount, qt.score, qt.answercount, qt.tag_array, ta.q_count, ta.total_views, ta.avg_score, atp.user_id, atp.displayname, atp.posts_in_tag, qt.comment_count, qt.vote_balance, qt.duplicate_links, qt.last_revision
)
select c.*,
       (coalesce(c.q_score, 0) * 1.5
        + ln(1 + coalesce(c.q_views, 0)) * 0.75
        + coalesce(c.q_answers, 0) * 2.0
        - sqrt(greatest(coalesce(c.sum_answer_penalties, 0), 0)) * 0.9
        + coalesce(c.tag_avg_score, 0) * 1.1
        + coalesce(c.posts_in_tag, 0) * 0.4
        - coalesce(c.duplicate_links, 0) * 5.0
        + (case when c.last_revision is null then -2 else 0 end)
       ) as composite_rank,
       substring(coalesce(c.title, '(no title)'), 1, 90) || ' [' || coalesce((
         select string_agg(distinct t.tag, ', ')
         from (
           select ta.tag
           from tag_aggregates ta
           join lateral (
             select unnest(c.tag_array) as tag
           ) x on ta.tag = x.tag
           limit 1
         ) t
       ), 'none') || ']' as title_snippet
from combined c
where (c.q_views > 100 or c.q_score >= 5 or c.q_answers >= 3 or c.tag_total_views > 1000)
  and (c.vote_balance is null or c.vote_balance > -5)
order by composite_rank desc, c.q_views desc
limit 100;