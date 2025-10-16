-- {"query": "121.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2633} 
with
-- questions and their parsed tags
q as (
  select p.id,
         p.title,
         p.creationdate,
         p.owneruserid,
         p.score,
         p.viewcount,
         p.answercount,
         p.favoritecount,
         p.tags,
         -- normalized tag array (nullable tags produce empty array)
         coalesce(
           nullif(trim(both ' ' from p.tags), ''),
           ''
         ) as raw_tags,
         case when p.posttypeid = 1 then true else false end as is_question
  from posts p
  where p.posttypeid = 1
),
parsed_tags as (
  select q.id as question_id,
         tag,
         trim(tag) as tag_clean
  from q,
       lateral (
         select unnest(
           case
             when length(coalesce(q.raw_tags,'')) > 2 then string_to_array(substring(q.raw_tags,2,length(q.raw_tags)-2), '><')
             else array[]::varchar[]
           end
         ) as tag
       ) t
  where tag is not null and tag <> ''
),
-- aggregate per tag
tag_agg as (
  select pt.tag_clean as tag,
         count(distinct pt.question_id) as questions,
         sum(coalesce(q.viewcount,0)) as total_views,
         avg(nullif(q.score,0)) filter (where q.score<>0) as avg_nonzero_score,
         max(q.favoritecount) as max_favorites
  from parsed_tags pt
  join q on q.id = pt.question_id
  group by pt.tag_clean
),
-- answers enriched with parent question info
answers as (
  select p.*,
         parent.title as parent_title,
         parent.tags as parent_tags,
         parent.owneruserid as question_ownerid
  from posts p
  left join posts parent on parent.id = p.parentid
  where p.posttypeid = 2
),
-- for each question, compute top answer score, accepted answer flag, and number of distinct answerers
question_answer_stats as (
  select q.id as question_id,
         q.title,
         q.creationdate,
         q.owneruserid,
         count(a.id) as answers_total,
         count(distinct a.owneruserid) filter (where a.owneruserid is not null) as distinct_answerers,
         max(a.score) as max_answer_score,
         min(a.score) as min_answer_score,
         bool_or(a.id = q.acceptedanswerid) as has_accepted,
         -- correlated subquery: time to first answer in seconds
         (
           select extract(epoch from (min(a2.creationdate) - q.creationdate))
           from posts a2
           where a2.parentid = q.id and a2.posttypeid = 2 and a2.creationdate is not null
         )::bigint as sec_to_first_answer
  from q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  group by q.id, q.title, q.creationdate, q.owneruserid, q.acceptedanswerid
),
-- compute per-user stats: posts, answers, questions, reputation, latest activity, badges
user_posts as (
  select u.id as user_id,
         u.reputation,
         u.displayname,
         count(distinct p.id) filter (where p.posttypeid in (1,2)) as posts_count,
         count(distinct p.id) filter (where p.posttypeid = 1) as questions_count,
         count(distinct p.id) filter (where p.posttypeid = 2) as answers_count,
         max(p.lastactivitydate) as last_post_activity,
         coalesce(u.views,0) as profile_views
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.reputation, u.displayname, u.views
),
user_badges as (
  select b.userid,
         count(*) as badge_total,
         count(*) filter (where b.class = 1) as gold,
         count(*) filter (where b.class = 2) as silver,
         count(*) filter (where b.class = 3) as bronze,
         count(*) filter (where b.tagbased = true) as tag_based
  from badges b
  group by b.userid
),
-- combine posts and badges with full outer join to stress join logic and null handling
user_profile as (
  select up.user_id,
         up.displayname,
         up.reputation,
         up.posts_count,
         up.questions_count,
         up.answers_count,
         up.last_post_activity,
         up.profile_views,
         coalesce(ub.badge_total,0) as badge_total,
         coalesce(ub.gold,0) as gold,
         coalesce(ub.silver,0) as silver,
         coalesce(ub.bronze,0) as bronze,
         coalesce(ub.tag_based,0) as tag_based
  from user_posts up
  full outer join user_badges ub on ub.userid = up.user_id
),
-- recent comments per post using DISTINCT ON (Postgres) to pick latest comment; fallback to null logic
latest_comments as (
  select distinct on (c.postid) c.postid,
         c.id as comment_id,
         c.creationdate as comment_date,
         left(c.text,200) as comment_snippet,
         c.userid
  from comments c
  where c.creationdate is not null
  order by c.postid, c.creationdate desc
),
-- window: rank top answerers per tag by total score of answers on that tag's questions
answers_with_tags as (
  select a.id as answer_id,
         a.owneruserid as answerer_id,
         pt.tag_clean as tag,
         a.score,
         a.creationdate
  from posts a
  join parsed_tags pt on pt.question_id = a.parentid
  where a.posttypeid = 2
),
top_answerers_by_tag as (
  select tag,
         answerer_id,
         sum(coalesce(score,0)) as total_answer_score,
         count(*) as answers_count,
         rank() over (partition by tag order by sum(coalesce(score,0)) desc, count(*) desc) as rnk
  from answers_with_tags
  group by tag, answerer_id
),
-- identify suspiciously fast accepted answers: accepted within X seconds and low score
fast_accepted as (
  select qas.question_id,
         qas.sec_to_first_answer,
         qas.max_answer_score,
         qas.has_accepted,
         qas.distinct_answerers,
         qas.answers_total,
         qas.title
  from question_answer_stats qas
  where qas.has_accepted = true
    and coalesce(qas.sec_to_first_answer, 99999999) < 3600
    and coalesce(qas.max_answer_score,0) < 2
),
-- combine several sets using set operators to introduce planning complexity
tag_hot_or_fast as (
  select tag as key, 'tag' as type, questions as metric1, total_views as metric2 from tag_agg where questions > 100
  union
  select 'fast_accepted' as key, 'flag' as type, count(*)::int as metric1, null::bigint as metric2 from fast_accepted
  union
  select t.tag, 'active' as type, t.questions, t.total_views from tag_agg t where t.total_views > 100000
),
-- final selection: diverse joins, window functions, complex predicates and calculations
final as (
  select
    t.tag,
    t.questions,
    t.total_views,
    t.avg_nonzero_score,
    t.max_favorites,
    -- top 3 answerers for this tag as comma-separated list (use subquery with array_agg)
    coalesce(
      (
        select string_agg(coalesce(u.displayname, 'user_'||a.answerer_id::text) || ':' || a.total_answer_score::text, ', ')
        from (
          select * from top_answerers_by_tag where tag = t.tag and rnk <= 3 order by total_answer_score desc nulls last
        ) a
        left join users u on u.id = a.answerer_id
      ),
      '(none)'
    ) as top_answerers,
    -- compute weighted popularity: total_views * log(questions+1) / nullif(avg_nonzero_score,0)
    (t.total_views::double precision * ln(t.questions + 1)) /
      nullif(coalesce(t.avg_nonzero_score, 0.0) + 1.0, 0.0) as weighted_popularity,
    -- latest question on this tag and its first answer delay (correlated subquery)
    (
      select q.id
      from parsed_tags pt2
      join posts q on q.id = pt2.question_id
      where pt2.tag_clean = t.tag
        and q.creationdate is not null
      order by q.creationdate desc
      limit 1
    ) as latest_question_id,
    (
      select (select extract(epoch from (min(a.creationdate) - q.creationdate))::bigint
       from posts a where a.parentid = q.id and a.posttypeid = 2)
      from parsed_tags pt2
      join posts q on q.id = pt2.question_id
      where pt2.tag_clean = t.tag
      order by q.creationdate desc
      limit 1
    ) as sec_to_first_for_latest
  from tag_agg t
  where t.tag is not null
),
-- union of two different summary rows to force set operators in plan
unioned_summary as (
  select tag as label, questions::text as a, total_views::text as b, round(weighted_popularity::numeric,2)::text as c from final
  union
  select key as label, metric1::text as a, coalesce(metric2,'')::text as b, null::text as c from tag_hot_or_fast
)
select
  us.user_id,
  us.displayname,
  us.reputation,
  us.posts_count,
  us.questions_count,
  us.answers_count,
  us.badge_total,
  us.gold,
  us.silver,
  us.bronze,
  -- user contribution: their total answers' average score and median recency (window)
  ua.avg_answer_score,
  ua.median_answer_age_days,
  -- join to latest comment on their posts
  lc.comment_id as latest_comment_id,
  lc.comment_date as latest_comment_date,
  -- include a sample of unioned summary rows (exists correlated subquery)
  (select count(*) from unioned_summary usum where usum.label is not null) as unioned_rows,
  -- boolean: is this user among current top answerers for any tag?
  exists (
    select 1 from top_answerers_by_tag tab where tab.answerer_id = us.user_id and tab.rnk = 1
  ) as is_top_answerer
from user_profile us
left join lateral (
  -- compute per-user aggregated answer metrics (window + percentile)
  select
    avg(coalesce(a.score,0)) as avg_answer_score,
    -- median age in days of answers (approx using percentile_cont)
    (extract(epoch from (now() - percentile_cont(0.5) within group (order by a.creationdate))) / 86400)::numeric(10,2) as median_answer_age_days
  from posts a
  where a.posttypeid = 2 and a.owneruserid = us.user_id
) ua on true
left join lateral (
  select * from latest_comments lc where lc.userid = us.user_id order by lc.comment_date desc limit 1
) lc on true
where coalesce(us.posts_count,0) > 0
order by us.reputation desc nulls last, us.posts_count desc
limit 200;