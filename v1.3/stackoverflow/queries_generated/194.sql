-- {"query": "194.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2584} 
with
-- explode tags per question
question_tags as (
  select p.id as question_id,
         trim(t.tag) as tag,
         p.creationdate,
         p.owneruserid,
         p.score,
         p.viewcount,
         p.answercount,
         p.favoritecount
  from posts p
  join posttypes pt on p.posttypeid = pt.id and pt.name ilike 'question'
  cross join lateral (
    select regexp_split_to_table(substring(coalesce(p.tags,''),2, greatest(length(coalesce(p.tags,'')) - 2,0)), '><') as tag
  ) t
),
-- aggregate tag-level metrics with windowing and rank
tag_aggregates as (
  select tag,
         count(*)                             as questions,
         sum(coalesce(viewcount,0))           as total_views,
         avg(coalesce(score,0))               as avg_score,
         sum(coalesce(answercount,0))         as total_answers,
         sum(coalesce(favoritecount,0))       as total_favorites,
         min(creationdate)                    as first_seen,
         max(creationdate)                    as last_seen,
         row_number() over (order by count(*) desc, sum(coalesce(viewcount,0)) desc) as popularity_rank
  from question_tags
  group by tag
),
-- per-question enriched stats including latest comment (correlated subquery) and last edit from history (left join)
question_enriched as (
  select q.id,
         q.title,
         q.tags,
         q.creationdate,
         q.owneruserid,
         q.score,
         q.viewcount,
         q.answercount,
         q.favoritecount,
         -- latest comment text (correlated)
         (select c.text from comments c where c.postid = q.id order by c.creationdate desc limit 1) as latest_comment,
         (select c.creationdate from comments c where c.postid = q.id order by c.creationdate desc limit 1) as latest_comment_date,
         ph.creationdate as last_edit_date,
         ph.userdisplayname as last_editor_name,
         -- simple heuristic: tag array length
         array_length(regexp_split_to_array(substring(coalesce(q.tags,''),2, greatest(length(coalesce(q.tags,'')) - 2,0)), '><'),1) as tag_count
  from posts q
  left join lateral (
    select ph_inner.creationdate, ph_inner.userid, ph_inner.userdisplayname
    from posthistory ph_inner
    where ph_inner.postid = q.id
    order by ph_inner.creationdate desc limit 1
  ) ph on true
  where q.posttypeid = (select id from posttypes where name ilike 'question' limit 1)
),
-- user-level activity: posts, answers, comments, badges, recency measures
user_activity as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate as user_created,
         count(distinct p.id) filter (where p.posttypeid = (select id from posttypes where name ilike 'question' limit 1)) as questions_posted,
         count(distinct p.id) filter (where p.posttypeid = (select id from posttypes where name ilike 'answer' limit 1)) as answers_posted,
         count(distinct c.id) as comments_posted,
         coalesce(sum(case when b.class = 1 then 1 else 0 end),0) as gold_badges,
         coalesce(sum(case when b.class = 2 then 1 else 0 end),0) as silver_badges,
         coalesce(sum(case when b.class = 3 then 1 else 0 end),0) as bronze_badges,
         greatest(max(p.lastactivitydate), max(c.creationdate)) as last_activity
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate
),
-- compute user effectiveness score (complex expression with nulls and safe division)
user_scores as (
  select ua.*,
         -- penalize inactivity, reward badges, high answer/question ratio, protect against division by zero/null
         (
           coalesce(ua.reputation,0) * 0.0005
           + coalesce(ua.answers_posted,0) * 0.2
           + (case when ua.questions_posted > 0 then (ua.answers_posted::numeric / nullif(ua.questions_posted,0)) else ua.answers_posted * 0.1 end)
           + (ua.gold_badges * 1.5 + ua.silver_badges * 0.5 + ua.bronze_badges * 0.1)
           - extract(epoch from (now() - coalesce(ua.last_activity, ua.user_created)))/ (60*60*24) * 0.01
         ) as effectiveness_score
  from user_activity ua
),
-- pair popular tags with their top contributors (answers+questions) using window functions and lateral join
tag_top_contributors as (
  select ta.tag,
         ua.user_id,
         ua.displayname,
         ua.questions_posted,
         ua.answers_posted,
         ua.comments_posted,
         ua.effectiveness_score,
         rank() over (partition by ta.tag order by ua.effectiveness_score desc) as contributor_rank
  from tag_aggregates ta
  join lateral (
    -- correlated subquery to find users who posted in that tag (approx by matching questions' owner)
    select u.id as user_id, u.displayname, ua2.questions_posted, ua2.answers_posted, ua2.comments_posted, us.effectiveness_score
    from question_tags qt
    join users u on u.id = qt.owneruserid
    join user_activity ua2 on ua2.user_id = u.id
    join user_scores us on us.user_id = u.id
    where qt.tag = ta.tag
    group by u.id, u.displayname, ua2.questions_posted, ua2.answers_posted, ua2.comments_posted, us.effectiveness_score
    order by us.effectiveness_score desc
    limit 10
  ) ua on true
),
-- combine posts with their linked posts (outer join both directions) and compute link-enrichment score
post_links_enriched as (
  select p.id as post_id,
         p.title,
         p.posttypeid,
         p.owneruserid,
         pl.relatedpostid,
         pl.linktypeid,
         lt.name as linktype_name,
         rp.title as related_title,
         rp.posttypeid as related_posttype,
         -- linkage age in days
         extract(epoch from (coalesce(pl.creationdate, now()) - p.creationdate))/(60*60*24) as link_age_days,
         -- a flag if link is reciprocal
         case when exists (select 1 from postlinks pl2 where pl2.postid = pl.relatedpostid and pl2.relatedpostid = pl.postid) then 1 else 0 end as reciprocal
  from posts p
  left join postlinks pl on pl.postid = p.id
  left join linktypes lt on lt.id = pl.linktypeid
  left join posts rp on rp.id = pl.relatedpostid
),
-- union/except example producing interesting set ops: recent hot questions vs historically top-viewed questions
recent_hot as (
  select id, title, creationdate, viewcount from posts
  where posttypeid = (select id from posttypes where name ilike 'question' limit 1)
    and creationdate >= now() - interval '30 days'
),
historical_top as (
  select id, title, creationdate, viewcount from posts
  where posttypeid = (select id from posttypes where name ilike 'question' limit 1)
    and viewcount > 10000
),
-- compute symmetric difference: recent hot that are not historically top and vice versa
hot_symdiff as (
  (select id, title, creationdate, viewcount, 'recent_only' as origin from recent_hot
    except
   select id, title, creationdate, viewcount from historical_top)
  union
  (select id, title, creationdate, viewcount, 'historical_only' as origin from historical_top
    except
   select id, title, creationdate, viewcount from recent_hot)
),
-- final combined analytics
final_analytics as (
  select
    qe.id as question_id,
    qe.title,
    qe.creationdate,
    qe.owneruserid,
    u.displayname as owner_name,
    ue.effectiveness_score as owner_score,
    qe.score,
    qe.viewcount,
    qe.answercount,
    qe.favoritecount,
    qe.tag_count,
    qe.latest_comment,
    qe.latest_comment_date,
    ta.tag as primary_tag,
    ta.popularity_rank,
    ta.questions as tag_question_count,
    ta.total_views as tag_total_views,
    coalesce(pl.reciprocal,0) as link_reciprocal_flag,
    pl.linktype_name,
    pl.related_title,
    -- a composite benchmark metric mixing tag popularity, owner score, and question traction
    (
      (coalesce(ta.popularity_rank::numeric,1000) * -1) * 0.2
      + coalesce(ue.effectiveness_score,0) * 0.4
      + log(1 + coalesce(qe.viewcount,0)) * 0.15
      + log(1 + coalesce(qe.answercount,0)) * 0.15
      + (case when qe.latest_comment_date is not null and qe.latest_comment_date >= now() - interval '7 days' then 2 else 0 end)
      - (case when qe.favoritecount is null then 0 else qe.favoritecount * 0.05 end)
    ) as benchmark_score
  from question_enriched qe
  left join users u on u.id = qe.owneruserid
  left join user_scores ue on ue.user_id = u.id
  left join lateral (
    select qf.tag, ta2.popularity_rank, ta2.questions, ta2.total_views
    from question_tags qf
    join tag_aggregates ta2 on ta2.tag = qf.tag
    where qf.question_id = qe.id
    order by ta2.popularity_rank asc
    limit 1
  ) ta on true
  left join lateral (
    select ple.reciprocal, ple.linktype_name, ple.related_title
    from post_links_enriched ple
    where ple.post_id = qe.id
    order by ple.reciprocal desc nulls last, ple.link_age_days asc
    limit 1
  ) pl on true
)
select
  fa.*,
  -- enrich with top 3 contributors for the primary tag as a JSON-like concatenation
  (
    select string_agg(format('%s(%.2f)', coalesce(ttc.displayname,'<anon>'), coalesce(ttc.effectiveness_score,0)), ' | ')
    from tag_top_contributors ttc
    where ttc.tag = fa.primary_tag and ttc.contributor_rank <= 3
  ) as top_contributors_for_tag,
  -- flag whether this question appears in the symmetric difference sets
  case when exists (select 1 from hot_symdiff hs where hs.id = fa.question_id) then true else false end as in_hot_symdiff
from final_analytics fa
order by fa.benchmark_score desc
limit 250;