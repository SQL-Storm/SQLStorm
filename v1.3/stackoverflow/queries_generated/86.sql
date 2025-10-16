-- {"query": "86.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2443} 
with
-- active users with weighted reputation momentum
user_momentum as (
  select u.id,
         u.displayname,
         u.reputation,
         greatest(0, extract(epoch from now() - u.creationdate)/86400) as days_alive,
         -- momentum = reputation growth per week (synthetic): reputation / sqrt(days_alive) * log1p(views)
         (u.reputation::numeric / nullif(sqrt(greatest(1, extract(epoch from now() - u.creationdate)/86400)),0) * ln(1 + coalesce(u.views,0) + 1))::numeric(18,6) as momentum
  from users u
  where u.reputation is not null
),
-- questions augmented with tag arrays and normalized title
questions as (
  select p.*,
         -- tags as array of individual tags (strip leading and trailing <>)
         case when p.tags is null then array[]::text[]
              else string_to_array(substr(p.tags,2, length(p.tags)-2), '><') end as tag_array,
         -- normalized short title for joins
         lower(regexp_replace(coalesce(p.title,''), '\s+', ' ','g')) as norm_title
  from posts p
  where p.posttypeid = 1
),
-- recent activity per post including last comment and last edit
post_activity as (
  select p.id as postid,
         p.owneruserid,
         p.title,
         p.creationdate,
         p.lastactivitydate,
         p.score,
         p.viewcount,
         p.answercount,
         p.acceptedanswerid,
         p.tag_array,
         -- last comment text and commenter
         (select c.text from comments c where c.postid = p.id order by c.creationdate desc limit 1) as last_comment_text,
         (select c.userid from comments c where c.postid = p.id order by c.creationdate desc limit 1) as last_comment_userid,
         -- last posthistory revision summary
         (select ph.posthistorytypeid || ':' || coalesce(substr(ph.comment,1,120),substr(ph.text::text,1,120))
            from posthistory ph where ph.postid = p.id order by ph.creationdate desc limit 1) as last_revision_summary
  from questions p
),
-- answers with parent question linkage and acceptance flags
answers as (
  select a.id as answerid,
         a.parentid as questionid,
         a.owneruserid,
         a.score,
         a.creationdate,
         a.body,
         a.lasteditdate,
         case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted,
         q.title as question_title,
         q.tag_array as question_tags,
         q.viewcount as question_views
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
),
-- tag popularity snapshot
tag_pop as (
  select t.tagname,
         t.count as tag_count,
         coalesce(tp.excerptpostid, tp.wikipostid) as tag_meta_postid,
         row_number() over (order by t.count desc) as popularity_rank
  from tags t
  where t.tagname is not null
),
-- aggregated badge stats per user
badge_agg as (
  select b.userid,
         count(*) filter (where b.class = 1) as gold_badges,
         count(*) filter (where b.class = 2) as silver_badges,
         count(*) filter (where b.class = 3) as bronze_badges,
         count(*) as total_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
-- per-question derived metrics combining multiple sources
question_metrics as (
  select pa.postid,
         pa.title,
         pa.creationdate,
         pa.lastactivitydate,
         pa.score,
         pa.viewcount,
         pa.answercount,
         pa.acceptedanswerid,
         pa.tag_array,
         pa.last_comment_text,
         pa.last_revision_summary,
         -- top scoring answer score and average answer score (correlated subqueries)
         (select max(coalesce(a.score,0)) from posts a where a.parentid = pa.postid and a.posttypeid = 2) as top_answer_score,
         (select avg(coalesce(a.score,0)) from posts a where a.parentid = pa.postid and a.posttypeid = 2) as avg_answer_score,
         -- number of distinct commenters (excluding anonymous displaynames)
         (select count(distinct coalesce(c.userid, -1)) from comments c where c.postid = pa.postid) as distinct_commenters,
         -- duplicate links count (via postlinks)
         (select count(*) from postlinks pl where pl.postid = pa.postid and pl.linktypeid = 3) as duplicate_count,
         -- presence of tag wiki or excerpt
         (select count(*) from tags tg where tg.excerptpostid in (pa.postid) or tg.wikipostid in (pa.postid)) as tag_meta_on_post,
         -- estimated freshness score: recency weight + last activity
         (extract(epoch from now() - pa.creationdate) / 86400)::int as days_since_creation,
         (extract(epoch from now() - coalesce(pa.lastactivitydate, pa.creationdate)) / 3600)::int as hours_since_last_activity
  from post_activity pa
),
-- rank questions within each tag by a composite hotness metric
tag_hotness as (
  select qm.postid,
         unnest(qm.tag_array) as tag,
         qm.title,
         qm.viewcount,
         qm.score,
         qm.answercount,
         qm.top_answer_score,
         qm.avg_answer_score,
         qm.distinct_commenters,
         -- composite hotness: view-weight + score-weight + recency penalty + activity bonus
         ((qm.viewcount::numeric * 0.001) + (coalesce(qm.score,0) * 2) + (coalesce(qm.top_answer_score,0) * 1.5) + (coalesce(qm.distinct_commenters,0) * 0.75)
           - least(365, qm.days_since_creation) * 0.05 + greatest(0, 48 - qm.hours_since_last_activity) * 0.2)::numeric(18,6) as hotness_score
  from question_metrics qm
),
-- pick top N per tag using window functions
top_per_tag as (
  select th.*,
         row_number() over (partition by th.tag order by th.hotness_score desc, th.viewcount desc, th.score desc) as rn
  from tag_hotness th
),
-- combine top questions with their top answers and author momentum
top_tag_summary as (
  select tpt.tag,
         tpt.postid,
         tpt.title,
         tpt.hotness_score,
         tpt.viewcount,
         tpt.score as question_score,
         coalesce(a.answerid, -1) as top_answer_id,
         coalesce(a.score,0) as top_answer_score,
         coalesce(ans_owner.displayname, 'unknown') as top_answer_owner,
         um.id as top_answer_owner_userid,
         um.momentum as top_answer_owner_momentum,
         -- flag for likely canonical: high hotness and accepted answer present
         case when qm.acceptedanswerid is not null and qm.acceptedanswerid = a.answerid then 1 else 0 end as accepted_flag,
         -- synthetic fingerprint for testing string ops
         md5(coalesce(tpt.title, '') || '|' || coalesce(tpt.tag,'')) as title_tag_hash
  from top_per_tag tpt
  left join question_metrics qm on qm.postid = tpt.postid
  left join lateral (
    select p2.id as answerid, p2.score, p2.owneruserid
    from posts p2
    where p2.parentid = tpt.postid and p2.posttypeid = 2
    order by p2.score desc nulls last
    limit 1
  ) a on true
  left join users ans_owner on ans_owner.id = a.owneruserid
  left join user_momentum um on um.id = ans_owner.id
  where tpt.rn <= 5
),
-- final aggregation mixing set operators and NULL logic to produce diverse plan shapes
final_union as (
  select 'HOT_TAG_TOP' as category, tts.* from top_tag_summary tts
  union all
  select 'RECENT_HIGH_SCORE', 
         tt.tag,
         qm1.postid,
         qm1.title,
         -- compute comparable fields with null-aware expressions
         (qm1.viewcount * 0.001 + coalesce(qm1.score,0) * 2 - qm1.days_since_creation * 0.02)::numeric(18,6) as hotness_score,
         qm1.viewcount,
         qm1.score,
         coalesce((select a.score from posts a where a.parentid = qm1.postid and a.posttypeid = 2 order by a.score desc limit 1),0) as top_answer_id,
         coalesce((select a.id from posts a where a.parentid = qm1.postid and a.posttypeid = 2 order by a.score desc limit 1), -1) as top_answer_score,
         coalesce((select u.displayname from users u where u.id = (select a.owneruserid from posts a where a.parentid = qm1.postid and a.posttypeid = 2 order by a.score desc limit 1)), 'unknown') as top_answer_owner,
         null::int as top_answer_owner_userid,
         null::numeric as top_answer_owner_momentum,
         case when qm1.acceptedanswerid is not null then 1 else 0 end as accepted_flag,
         md5(coalesce(qm1.title,'') || '|' || coalesce(array_to_string(qm1.tag_array,','),'')) as title_tag_hash
  from question_metrics qm1
  cross join lateral (
    select unnest(qm1.tag_array) as tag
  ) tt
  where qm1.score >= 10 and qm1.days_since_creation <= 30
),
-- final selection with ordering, windowing and complex predicates
final_selection as (
  select fu.category,
         fu.tag,
         fu.postid,
         fu.title,
         fu.hotness_score,
         fu.viewcount,
         fu.question_score,
         fu.top_answer_id,
         fu.top_answer_score,
         fu.top_answer_owner,
         fu.top_answer_owner_userid,
         fu.top_answer_owner_momentum,
         fu.accepted_flag,
         fu.title_tag_hash,
         dense_rank() over (partition by fu.tag order by fu.hotness_score desc) as tag_rank,
         rank() over (order by fu.hotness_score desc nulls last, fu.viewcount desc) as global_rank
  from final_union fu
)
select *
from final_selection
where -- complex predicate mixing null logic, modulo and string pattern checks
      (accepted_flag = 1 or (coalesce(top_answer_owner_momentum,0) > 50 and (hotness_score > 5 or viewcount > 1000)))
  and (tag_rank <= 3 or global_rank <= 100)
  and (title ~* 'error|exception|timeout' or length(coalesce(title,'')) > 40 or hotness_score > 10)
order by global_rank, tag, hotness_score desc, postid
limit 500;