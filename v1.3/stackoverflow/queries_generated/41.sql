-- {"query": "41.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2585} 
with
-- active users: recent activity and contribution metrics
user_activity as (
  select u.id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.lastaccessdate,
         coalesce(u.location,'') as location,
         coalesce(u.websiteurl,'') as website,
         -- compute weighted score from badges and reputation/time
         (u.reputation * 0.6
           + coalesce(b.badge_score,0) * 10
           + greatest(0, date_part('day', now() - u.creationdate)) / greatest(1, nullif(date_part('day', now() - u.creationdate),0)) )::numeric(18,4) as user_score,
         b.badge_score,
         b.gold_badges,
         b.silver_badges,
         b.bronze_badges
  from users u
  left join (
    select userId,
           sum(case when class=1 then 5 when class=2 then 3 else 1 end) as badge_score,
           sum(case when class=1 then 1 else 0 end) as gold_badges,
           sum(case when class=2 then 1 else 0 end) as silver_badges,
           sum(case when class=3 then 1 else 0 end) as bronze_badges
    from badges
    group by userId
  ) b on b.userId = u.id
  where u.id is not null
),
-- questions with enriched stats, tags exploded
questions as (
  select p.id,
         p.title,
         p.creationdate,
         p.owneruserid,
         p.score,
         p.viewcount,
         p.answercount,
         p.favoritecount,
         coalesce(p.tags,'') as tags,
         -- normalized tag list as rows via regexp split (works in PG; adapt if needed)
         regexp_split_to_array(substring(coalesce(p.tags,''),2, greatest(0,length(coalesce(p.tags,''))-2)), '><') as tag_array,
         p.lastactivitydate
  from posts p
  where p.posttypeid = 1
),
-- explode tags into one row per tag per question
question_tags as (
  select q.*,
         tag,
         row_number() over (partition by q.id order by (select null)) as tag_seq
  from questions q
  cross join lateral unnest(q.tag_array) as tag
),
-- compute per-question derived metrics with correlated subqueries and window functions
question_stats as (
  select qt.id,
         qt.title,
         qt.creationdate,
         qt.owneruserid,
         qt.score,
         qt.viewcount,
         qt.answercount,
         qt.favoritecount,
         qt.tag,
         qt.lastactivitydate,
         -- age in days
         greatest(0, date_part('day', now() - qt.creationdate))::int as age_days,
         -- ratio metrics with safe null handling
         case when qt.viewcount > 0 then round(qt.score::numeric / qt.viewcount::numeric,8) else 0 end as score_per_view,
         case when qt.answercount > 0 then round(qt.favoritecount::numeric / qt.answercount::numeric,8) else qt.favoritecount end as fav_per_answer,
         -- count of answers and accepted answer existence via correlated subquery
         (select count(1) from posts a where a.parentid = qt.id and a.posttypeid = 2) as answers_total,
         (select a.id from posts a where a.parentid = qt.id and a.id = qt.acceptedanswerid limit 1) is not null as has_accepted,
         -- last comment text shortened via lateral
         (select substring(c.text from 1 for 200) from comments c where c.postid = qt.id order by c.creationdate desc limit 1) as latest_comment_snippet
  from question_tags qt
),
-- compute user contribution aggregates joining posts, answers, votes, and links with outer joins and set operators
user_contribs as (
  select ua.id as user_id,
         ua.displayname,
         ua.user_score,
         ua.gold_badges,
         ua.silver_badges,
         ua.bronze_badges,
         coalesce(qs.question_count,0) as question_count,
         coalesce(ans.answer_count,0) as answer_count,
         coalesce(v.upvotes_received,0) as upvotes_received,
         coalesce(v.downvotes_received,0) as downvotes_received,
         coalesce(link.outbound_links,0) as outbound_links,
         coalesce(link.inbound_links,0) as inbound_links,
         -- composite metric
         (ua.user_score + coalesce(ans.answer_count,0)*2 + coalesce(qs.question_count,0)*1.5 + coalesce(v.upvotes_received,0)*0.5 - coalesce(v.downvotes_received,0)*0.25
           + coalesce(link.inbound_links,0)*0.1) as contrib_score
  from user_activity ua
  left join (
    select owneruserid, count(1) as question_count
    from posts
    where posttypeid = 1
    group by owneruserid
  ) qs on qs.owneruserid = ua.id
  left join (
    select owneruserid, count(1) as answer_count
    from posts
    where posttypeid = 2
    group by owneruserid
  ) ans on ans.owneruserid = ua.id
  left join (
    select p.owneruserid,
           sum(case when vt.name ilike 'UpMod' or vt.id=2 then 1 else 0 end) as upvotes_received,
           sum(case when vt.name ilike 'DownMod' or vt.id=3 then 1 else 0 end) as downvotes_received
    from votes v
    join votetypes vt on vt.id = v.votetypeid
    join posts p on p.id = v.postid
    group by p.owneruserid
  ) v on v.owneruserid = ua.id
  left join (
    select p.owneruserid,
           sum(case when pl.postid = p.id then 1 else 0 end) filter (where pl.postid is not null) as outbound_links,
           sum(case when pl.relatedpostid = p.id then 1 else 0 end) filter (where pl.relatedpostid is not null) as inbound_links
    from posts p
    left join postlinks pl on pl.postid = p.id or pl.relatedpostid = p.id
    group by p.owneruserid
  ) link on link.owneruserid = ua.id
),
-- heavy-weight complex windowed ranking across tags and time-sliced aggregates
tag_trends as (
  select t.tag,
         date_trunc('month', q.creationdate) as month,
         count(distinct q.id) as questions_in_month,
         sum(q.viewcount) as views_in_month,
         sum(q.score) as score_in_month,
         avg(q.score_per_view) as avg_score_per_view,
         -- trend: compare to previous month using lag
         lag(count(distinct q.id)) over (partition by t.tag order by date_trunc('month', q.creationdate)) as prev_month_questions,
         case when lag(count(distinct q.id)) over (partition by t.tag order by date_trunc('month', q.creationdate)) is not null
              then round((count(distinct q.id) - lag(count(distinct q.id)) over (partition by t.tag order by date_trunc('month', q.creationdate)))::numeric
                         / nullif(lag(count(distinct q.id)) over (partition by t.tag order by date_trunc('month', q.creationdate)),0)::numeric,4)
              else null end as month_growth_rate
  from question_stats q
  join lateral (select distinct q.tag) t(tag) on true
  group by t.tag, date_trunc('month', q.creationdate)
),
-- identify anomalous questions via correlated subqueries and boolean expressions
anomalies as (
  select qs.*,
         uc.displayname as owner_name,
         uc.contrib_score,
         -- anomaly flags
         (case when qs.viewcount > 100000 and qs.score < 0 then true else false end) as high_views_negative_score,
         (case when qs.age_days < 7 and qs.answers_total > 100 then true else false end) as rapid_answers,
         -- fuzzy title complexity: count distinct words and punctuation density
         (select count(*) from unnest(regexp_split_to_array(coalesce(qs.title,''), '\s+')) w where w <> '') as title_word_count,
         (length(coalesce(qs.title,'')) - length(replace(coalesce(qs.title,''), ' ', '')) )::int as title_space_count
  from question_stats qs
  left join user_contribs uc on uc.user_id = qs.owneruserid
),
-- pick top contributors and tag hotspots with set operations
top_contribs as (
  select user_id, displayname, contrib_score, question_count, answer_count
  from user_contribs
  order by contrib_score desc nulls last
  limit 100
),
-- union of recent hot questions by views and by score to create a diverse set
hot_by_views as (
  select id, title, viewcount as metric_value, 'views' as metric_type from posts where posttypeid=1 and viewcount is not null order by viewcount desc limit 200
),
hot_by_score as (
  select id, title, score as metric_value, 'score' as metric_type from posts where posttypeid=1 and score is not null order by score desc limit 200
),
hot_union as (
  select * from hot_by_views
  union
  select * from hot_by_score
),
-- final selection with complex joins, null logic, and ordering, including set operators to combine result sets
final_set as (
  select a.id as question_id,
         a.title,
         a.metric_type,
         a.metric_value,
         q.title as canonical_title,
         q.tag,
         q.score as q_score,
         q.viewcount as q_views,
         q.answercount,
         q.has_accepted,
         uc.displayname as owner_name,
         uc.contrib_score,
         t.month as trend_month,
         t.questions_in_month,
         t.month_growth_rate,
         an.high_views_negative_score,
         an.rapid_answers,
         an.title_word_count,
         an.latest_comment_snippet
  from hot_union a
  left join question_stats q on q.id = a.id
  left join user_contribs uc on uc.user_id = q.owneruserid
  left join tag_trends t on t.tag = q.tag and t.month = (select max(month) from tag_trends t2 where t2.tag = q.tag)
  left join anomalies an on an.id = q.id
  where (a.metric_value is not null)
)
select distinct fs.*,
       -- computed hazard score mixing null-sensitive expressions and window percentiles
       (coalesce(fs.metric_value,0)::numeric * 0.4
        + coalesce(fs.contrib_score,0)::numeric * 0.3
        + coalesce(fs.questions_in_month,0)::numeric * 0.2
        - coalesce(fs.month_growth_rate,0)::numeric * 50
        + case when fs.high_views_negative_score then 100 else 0 end
        - case when fs.rapid_answers then 50 else 0 end) as hazard_score,
       -- percentile rank of hazard_score among final_set
       (percent_rank() over (order by (coalesce(fs.metric_value,0)::numeric * 0.4
                                       + coalesce(fs.contrib_score,0)::numeric * 0.3
                                       + coalesce(fs.questions_in_month,0)::numeric * 0.2
                                       - coalesce(fs.month_growth_rate,0)::numeric * 50
                                       + case when fs.high_views_negative_score then 100 else 0 end
                                       - case when fs.rapid_answers then 50 else 0 end)) ) as hazard_percentile
from final_set fs
where fs.title is not null
order by hazard_score desc nulls last, fs.metric_value desc
limit 500;