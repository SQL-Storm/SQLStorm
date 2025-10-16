-- {"query": "92.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2165} 
with
-- recent active users with weighted reputation trend
user_trend as (
  select u.Id as UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         -- recency weight: newer activity counts more
         greatest(0, extract(epoch from (now() - u.LastAccessDate))/86400) as days_idle,
         -- long-term activity signal from badges and post counts (subqueries)
         (select count(*) from Badges b where b.UserId = u.Id) as badge_count,
         (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as question_count,
         (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as answer_count,
         -- composite score (arbitrary non-linear formula)
         (u.Reputation * 0.5
          + coalesce((select sum(case when Class=1 then 50 when Class=2 then 20 else 5 end) from Badges b where b.UserId = u.Id),0) * 1.5
          + coalesce((select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2),0) * 3
          - greatest(0, extract(epoch from (now() - u.LastAccessDate))/86400) * 0.2
         ) as influence_score
  from Users u
  where u.Reputation > 100
),
-- heavy questions with tag parsing and aggregated metrics
question_metrics as (
  select q.Id as QuestionId,
         q.Title,
         q.OwnerUserId,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         q.FavoriteCount,
         -- split tags to rows: emulate string_to_array on Tags format '<tag1><tag2>'
         regexp_split_to_table(substring(coalesce(q.Tags,''),2, greatest(0,length(coalesce(q.Tags,'')) - 2)), '><') as tag
  from Posts q
  where q.PostTypeId = 1
),
-- tag popularity and volatility windowed over questions
tag_aggregates as (
  select tag,
         count(*) as q_count,
         sum(AnswerCount) as total_answers,
         avg(Score) as avg_score,
         max(ViewCount) as max_views,
         min(CreationDate) as first_seen,
         max(CreationDate) as last_seen,
         -- volatility: normalized stddev of scores
         coalesce(stddev_samp(Score)::double precision,0) as score_stddev
  from (
    select qm.*, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate
    from question_metrics qm
    join Posts p on p.Id = qm.QuestionId
  ) s
  group by tag
),
-- links graph: questions linked and duplicates
link_graph as (
  select pl.PostId as FromPost,
         pl.RelatedPostId as ToPost,
         lt.Name as LinkType,
         pl.CreationDate
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
),
-- compute for each question: incoming duplicates, outgoing links, avg linked score
question_links as (
  select q.Id as QuestionId,
         q.Title,
         q.Score,
         sum(case when lg.LinkType = 'Duplicate' and lg.ToPost = q.Id then 1 else 0 end) over (partition by q.Id) as incoming_duplicates,
         sum(case when lg.LinkType = 'Duplicate' and lg.FromPost = q.Id then 1 else 0 end) over (partition by q.Id) as outgoing_duplicates,
         coalesce(avg(lq.Score) filter (where lq.PostTypeId = 2),0) as avg_linked_answer_score
  from Posts q
  left join link_graph lg on lg.ToPost = q.Id or lg.FromPost = q.Id
  left join Posts lq on lq.Id = lg.RelatedPostId
  where q.PostTypeId = 1
  group by q.Id, q.Title, q.Score
),
-- compute per-question top commenters and commenter diversity
comment_stats as (
  select p.Id as PostId,
         count(c.Id) as comment_count,
         count(distinct c.UserId) as commenter_distinct,
         max(c.Score) as max_comment_score,
         -- top commenter by number of comments (ties broken by earliest)
         (select c2.UserId from Comments c2 where c2.PostId = p.Id and c2.UserId is not null group by c2.UserId order by count(*) desc, min(c2.CreationDate) asc limit 1) as top_commenter_id,
         -- a concatenated sample of comment texts (limited)
         string_agg(substring(coalesce(c.Text,''),1,80), ' || ' order by c.CreationDate desc) as recent_comment_snippets
  from Posts p
  left join Comments c on c.PostId = p.Id
  where p.PostTypeId = 1
  group by p.Id
),
-- per-answer derived metrics with correlated subqueries to estimate helpfulness
answer_quality as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId,
         a.Score as answer_score,
         a.CreationDate,
         a.CommunityOwnedDate,
         -- is accepted?
         case when exists (select 1 from Posts q where q.Id = a.ParentId and q.AcceptedAnswerId = a.Id) then 1 else 0 end as is_accepted,
         -- relative score vs question
         (a.Score::double precision / nullif((select Score from Posts q where q.Id = a.ParentId),0)) as rel_to_question_score,
         -- count of upvotes vs downvotes via VoteTypes (requires mapping; assume 2=UpMod,3=DownMod)
         coalesce((select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2),0) as upvotes,
         coalesce((select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3),0) as downvotes,
         -- answer age in hours
         extract(epoch from (now() - a.CreationDate))/3600.0 as hours_since_posted,
         -- textual richness: length of body, count of code blocks (heuristic: occurrences of '<code>')
         length(coalesce(a.Body,'')) as body_len,
         (length(coalesce(a.Body,'')) - length(replace(coalesce(a.Body,''), '<code','')))/5 as approx_code_blocks
  from Posts a
  where a.PostTypeId = 2
),
-- join everything and compute a composite benchmark score with window functions
final_rank as (
  select q.Id as QuestionId,
         q.Title,
         ta.tag,
         ta.q_count,
         ta.avg_score as tag_avg_score,
         qa.incoming_duplicates,
         qa.outgoing_duplicates,
         cs.comment_count,
         cs.commenter_distinct,
         aq.AnswerId,
         aq.answer_score,
         aq.is_accepted,
         aq.upvotes,
         aq.downvotes,
         aq.hours_since_posted,
         aq.body_len,
         row_number() over (partition by q.Id order by aq.is_accepted desc, aq.answer_score desc, aq.upvotes desc, aq.hours_since_posted asc nulls last) as answer_rank,
         -- composite benchmark metric mixing tag popularity, question score, answer quality, and network signals
         (
           coalesce(q.Score,0) * 1.2
           + coalesce(aq.answer_score,0) * 2.5
           + coalesce(ta.q_count,0) * 0.3
           + (case when aq.is_accepted = 1 then 50 else 0 end)
           + greatest(0, (cs.comment_count - 2)) * 1.1
           - coalesce(qa.incoming_duplicates,0) * 5
           + logarith(1 + greatest(0, qa.avg_linked_answer_score)) * 10
           + (case when aq.body_len > 1000 then 20 when aq.body_len > 300 then 8 else 0 end)
           - aq.hours_since_posted * 0.01
         ) as benchmark_score
  from Posts q
  join question_metrics qm on qm.QuestionId = q.Id
  left join tag_aggregates ta on ta.tag = qm.tag
  left join question_links qa on qa.QuestionId = q.Id
  left join comment_stats cs on cs.PostId = q.Id
  left join answer_quality aq on aq.QuestionId = q.Id
  where q.Score is not null
)
select *
from (
  select fr.*,
         -- windowed percentile rank across all final entries
         percent_rank() over (order by benchmark_score desc) as percentile_rank,
         -- dense rank for tie grouping
         dense_rank() over (order by benchmark_score desc) as dense_rank_desc,
         -- top correlated active users (owners or top commenter) via lateral correlated subquery
         (select json_agg(json_build_object('user_id', u.Id, 'display', u.DisplayName, 'influence', ut.influence_score) order by ut.influence_score desc)
          from (
            select distinct coalesce(fr_owner.Id, fr_topc.Id) as uid
            from (values (fr.QuestionId)) v(qid) -- placeholder to reference outer fr
            left join Posts powner on powner.Id = fr.QuestionId
            left join Users fr_owner on fr_owner.Id = powner.OwnerUserId
            left join Users fr_topc on fr_topc.Id = cs.top_commenter_id
            limit 1
          ) x(uid)
          left join Users u on u.Id = x.uid
          left join user_trend ut on ut.UserId = u.Id
         ) as related_users_json
  from final_rank fr
) t
where answer_rank <= 3
order by benchmark_score desc
limit 200;