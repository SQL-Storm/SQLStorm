-- {"query": "107.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2448} 
with
-- recent questions and parsed tags
recent_q as (
  select p.id, p.title, p.owneruserid, p.creationdate, p.score, p.viewcount, p.tags,
    -- parse tags into array (tags are like '<tag1><tag2>')
    case when p.tags is null then '{}'::text[] else string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end as tag_array
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '2 years'
),
-- exploded tags for tag-level aggregates
q_tags as (
  select rq.*, unnest(rq.tag_array) as tag
  from recent_q rq
),
-- answers and link to their parent questions
answers as (
  select a.id, a.parentid, a.owneruserid, a.creationdate, a.score, a.body,
    row_number() over (partition by a.parentid order by a.score desc, a.creationdate asc) as answer_rank
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= now() - interval '2 years'
),
-- aggregated votes per post with conditional expressions and null-safe math
votes_agg as (
  select v.postid,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
    count(*) filter (where v.votetypeid = 5) as favorites,
    sum(case when v.bountyamount is not null then v.bountyamount else 0 end) as total_bounty_amount,
    max(v.creationdate) as last_vote_date
  from votes v
  group by v.postid
),
-- recent comments per post and comment sentiment proxy using text length and presence of 'thanks' (toy example)
comments_agg as (
  select c.postid,
    count(*) as comment_count,
    max(c.creationdate) as last_comment,
    avg(char_length(c.text)) as avg_comment_len,
    sum(case when lower(c.text) like '%thanks%' then 1 else 0 end) as thanks_count
  from comments c
  group by c.postid
),
-- edit activity and close events from posthistory
history_agg as (
  select ph.postid,
    count(*) as history_events,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as substantive_edits,
    max(case when ph.posthistorytypeid in (10,11,12,13) then ph.creationdate else null end) as last_close_reopen_date,
    string_agg(distinct coalesce(ph.comment, '') , ' | ' order by ph.creationdate desc) as recent_history_comments
  from posthistory ph
  group by ph.postid
),
-- user-level aggregates for owners
user_stats as (
  select u.id as userid, u.displayname, u.reputation, u.creationdate as user_created,
    (extract(epoch from now() - u.lastaccessdate)/86400)::int as days_since_last_access,
    coalesce(u.views,0) as profile_views,
    count(b.id) filter (where b.class = 1) as gold_badges,
    count(b.id) filter (where b.class = 2) as silver_badges,
    count(b.id) filter (where b.class = 3) as bronze_badges
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.views
),
-- combine question-level metrics
question_metrics as (
  select rq.id as question_id,
    rq.title,
    rq.owneruserid,
    rq.creationdate as question_created,
    rq.score as question_score,
    rq.viewcount as question_views,
    rq.tags,
    coalesce(v.net_votes,0) as net_votes,
    coalesce(v.favorites,0) as favorites,
    coalesce(c.comment_count,0) as comment_count,
    coalesce(h.substantive_edits,0) as edits,
    coalesce(a.answer_count,0) as answer_count,
    a.top_answer_id,
    a.top_answer_score,
    -- engagement index: weighted combination with null-safe operations
    (coalesce(v.net_votes,0)*1.5 + coalesce(c.comment_count,0)*1.2 + coalesce(a.answer_count,0)*2 + coalesce(rq.viewcount,0)/100.0 + coalesce(v.favorites,0)*3 - coalesce(h.substantive_edits,0)*0.5) as engagement_score,
    -- tag popularity proxy: average question score for primary tag (correlated subquery)
    (
      select avg(p2.score)::numeric
      from posts p2
      where p2.posttypeid = 1
        and p2.tags is not null
        and substring(p2.tags from 2 for char_length(p2.tags)-2) like '%' || split_part(substring(rq.tags from 2 for char_length(rq.tags)-2), '><', 1) || '%'
        and p2.creationdate >= now() - interval '5 years'
    )::numeric as primary_tag_avg_score
  from recent_q rq
  left join votes_agg v on v.postid = rq.id
  left join comments_agg c on c.postid = rq.id
  left join history_agg h on h.postid = rq.id
  left join (
    -- answers summary per question via aggregation and correlated top answer selection
    select parentid,
      count(*) as answer_count,
      max(score) as top_answer_score,
      min(id) filter (where score = max(score) over (partition by parentid)) as top_answer_id
    from posts p
    where p.posttypeid = 2
    group by parentid
  ) a on a.parentid = rq.id
),
-- heavy windowed ranking and moving averages for temporal benchmarking
ranked_questions as (
  select qm.*,
    rank() over (order by engagement_score desc nulls last) as engagement_rank,
    row_number() over (partition by date_trunc('month', question_created) order by engagement_score desc) as month_rank,
    avg(engagement_score) over (order by question_created rows between 30 preceding and current row) as rolling_30_row_engagement_avg
  from question_metrics qm
),
-- tag-level top contributors via set operator combination of owners and top-answerers
tag_owners as (
  select distinct qt.tag, u.id as userid, u.displayname
  from q_tags qt
  join users u on u.id = qt.owneruserid
),
tag_top_answerers as (
  select distinct unnest(string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><')) as tag, a.owneruserid as userid
  from posts p
  join posts a on a.parentid = p.id and a.posttypeid = 2
  where p.posttypeid = 1
),
tag_contributors as (
  select tag, userid from tag_owners
  union
  select tag, userid from tag_top_answerers
),
tag_contrib_counts as (
  select tc.tag, tc.userid, us.displayname,
    count(*) over (partition by tc.tag, tc.userid) as contrib_count,
    row_number() over (partition by tc.tag order by count(*) over (partition by tc.tag, tc.userid) desc) as contrib_rank
  from tag_contributors tc
  left join user_stats us on us.userid = tc.userid
),
-- final selection with complicated predicates and null handling
final_candidates as (
  select rq.*,
    us.displayname as owner_name,
    us.reputation as owner_reputation,
    coalesce(us.gold_badges,0) as owner_gold,
    coalesce(us.silver_badges,0) as owner_silver,
    coalesce(us.bronze_badges,0) as owner_bronze,
    qc.primary_tag_avg_score,
    qc.engagement_score,
    rq.engagement_rank,
    case
      when qc.primary_tag_avg_score is null then 'unknown'
      when qc.primary_tag_avg_score > 10 then 'hot-tag'
      when qc.primary_tag_avg_score between 3 and 10 then 'warm-tag'
      else 'cold-tag'
    end as tag_popularity_bucket
  from ranked_questions rq
  join question_metrics qc on qc.question_id = rq.question_id
  left join user_stats us on us.userid = rq.owneruserid
  where (qc.engagement_score is not null and qc.engagement_score > 5)
    or (coalesce(us.reputation,0) > 10000 and coalesce(qc.engagement_score,0) > 1)
)
-- produce top 50 with supplemental correlated subqueries and a set operator example
select fc.question_id,
  fc.title,
  fc.owner_name,
  fc.owner_reputation,
  fc.owner_gold, fc.owner_silver, fc.owner_bronze,
  fc.question_created,
  fc.question_score,
  fc.question_views,
  fc.engagement_score,
  fc.engagement_rank,
  fc.tag_popularity_bucket,
  fc.primary_tag_avg_score,
  -- correlated: count of distinct answerers for this question in last year
  (select count(distinct a.owneruserid) from posts a where a.posttypeid = 2 and a.parentid = fc.question_id and a.creationdate >= now() - interval '1 year') as distinct_answerers_last_year,
  -- correlated: latest comment text (may be null)
  (select c.text from comments c where c.postid = fc.question_id order by c.creationdate desc limit 1) as latest_comment_excerpt,
  -- string expression combining title and tag bucket with null-safe concat
  coalesce(fc.title, '(no title)') || ' [' || fc.tag_popularity_bucket || ']' as title_with_bucket
from final_candidates fc
where fc.question_created >= now() - interval '18 months'
order by fc.engagement_score desc nulls last, fc.owner_reputation desc
limit 50

-- set operator example: exclude any questions that are exactly matched by a low-engagement sample (EXCEPT)
except

select q.id, q.title, u.displayname, u.reputation, q.creationdate, q.score, q.viewcount, null::numeric, null::int, null::int, null::int, null::text, null::numeric, null::text
from posts q
left join users u on u.id = q.owneruserid
where q.posttypeid = 1
  and q.creationdate >= now() - interval '18 months'
  and q.score <= 0
  and (select count(*) from comments c where c.postid = q.id) < 2
order by q.creationdate desc
limit 100;