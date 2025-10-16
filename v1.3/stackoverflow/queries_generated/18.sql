-- {"query": "18.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2547} 
with
-- active users: have at least one post or comment in last year, plus computed influence score
ActiveUsers as (
  select u.Id,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         coalesce(u.Location,'(unknown)') as Location,
         count(distinct p.Id) filter (where p.CreationDate >= now() - interval '1 year') as RecentPosts,
         count(distinct c.Id) filter (where c.CreationDate >= now() - interval '1 year') as RecentComments,
         -- influence: weighted combination of reputation, recent activity, badges and average post score
         (u.Reputation::numeric * 0.4
          + greatest(0, count(b.Id)) * 10
          + coalesce(avg(p.Score),0) * 5
          + (count(distinct p.Id) filter (where p.Score > 0 and p.CreationDate >= now() - interval '1 year')) * 3
         ) as InfluenceScore
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
  having (count(distinct p.Id) filter (where p.CreationDate >= now() - interval '1 year') 
          + count(distinct c.Id) filter (where c.CreationDate >= now() - interval '1 year')) >= 1
),

-- find question threads with at least one accepted answer or high score answers, enriched with tag extraction
QuestionThreads as (
  select q.Id as QuestionId,
         q.Title,
         q.OwnerUserId,
         q.AcceptedAnswerId,
         q.CreationDate as QuestionCreated,
         q.Score as QuestionScore,
         q.ViewCount,
         q.Tags,
         -- extract first 3 tags in a normalized way (Tags stored as: '<tag1><tag2>...')
         regexp_split_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><') [1:3] as TopThreeTags,
         -- number of answers, and best answer score
         count(a.Id) filter (where a.PostTypeId = 2) as AnswerCount,
         max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore,
         avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
         -- days to accepted answer (null if none)
         case when q.AcceptedAnswerId is not null then
           extract(epoch from (aa.CreationDate - q.CreationDate))/86400.0
         end as DaysToAccepted
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join Posts aa on aa.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1
  group by q.Id, q.Title, q.OwnerUserId, q.AcceptedAnswerId, q.CreationDate, q.Score, q.ViewCount, q.Tags
),

-- correlate posts linked as duplicates and backlinks
DuplicateGraph as (
  select pl.PostId as SourceId,
         pl.RelatedPostId as TargetId,
         lt.Name as LinkType,
         count(*) over (partition by pl.PostId, pl.RelatedPostId) as LinkCount
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  where pl.LinkTypeId in (3,1) -- duplicates and generic links
),

-- compute moving averages and rank answers per question using window functions and NULL-aware math
RankedAnswers as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId,
         a.CreationDate,
         a.Score,
         a.ViewCount,
         a.CommentCount,
         a.Body,
         -- sentiment-ish heuristics: presence of 'thank', 'thanks', 'solved' (case-insensitive)
         (case when a.Body ~* '\m(thank|thanks|solved|fixed|worked)\M' then 1 else 0 end) as GratitudeFlag,
         -- normalized score with damping and null handling
         coalesce((a.Score::numeric) / nullif(1 + sqrt(greatest(a.ViewCount,0)),0), 0) as NormScore,
         -- window-based rank within question
         row_number() over (partition by a.ParentId order by coalesce(a.Score,0) desc, a.CreationDate asc) as AnswerRank,
         rank() over (partition by a.ParentId order by coalesce(a.Score,0) desc) as AnswerDenseRank,
         -- moving average score of last 5 answers per question by creation date
         avg(a.Score) over (partition by a.ParentId order by a.CreationDate rows between 4 preceding and current row) as MovingAvgScore5
  from Posts a
  where a.PostTypeId = 2
),

-- pair active users with their top contributions and neighbor effects (neighbors = users who commented on same posts)
UserContribs as (
  select au.Id as UserId,
         au.DisplayName,
         au.InfluenceScore,
         -- count of questions and answers authored in last 2 years
         sum(case when p.PostTypeId = 1 and p.CreationDate >= now() - interval '2 year' then 1 else 0 end) as Questions2y,
         sum(case when p.PostTypeId = 2 and p.CreationDate >= now() - interval '2 year' then 1 else 0 end) as Answers2y,
         -- average answer normalized score for user's answers
         avg(case when p.PostTypeId = 2 then coalesce(p.Score,0)/nullif(greatest(p.ViewCount,1),0) end) as AvgAnswerNorm,
         -- distinct tags they participated in (via questions they asked)
         array_agg(distinct t.TagName) filter (where p.PostTypeId = 1) as TagsParticipated
  from ActiveUsers au
  left join Posts p on p.OwnerUserId = au.Id
  left join LATERAL (
    select unnest(regexp_split_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
  ) t on p.PostTypeId = 1 and p.Tags is not null
  group by au.Id, au.DisplayName, au.InfluenceScore
),

-- neighbors: users who commented on posts the user authored (correlated subquery)
UserNeighbors as (
  select uc.UserId,
         n.UserId as NeighborId,
         count(distinct c.PostId) as SharedPostsCount,
         max(n.Reputation) as NeighborMaxReputation
  from UserContribs uc
  join Posts p on p.OwnerUserId = uc.UserId
  join Comments c on c.PostId = p.Id
  join Users n on n.Id = c.UserId
  where n.Id is not null and n.Id <> uc.UserId
  group by uc.UserId, n.UserId
),

-- heavy aggregated benchmark: compute complex score per question combining many signals
QuestionComposite as (
  select qt.QuestionId,
         qt.Title,
         qt.OwnerUserId,
         qt.QuestionCreated,
         qt.QuestionScore,
         qt.ViewCount,
         qt.TopThreeTags,
         qt.AnswerCount,
         qt.MaxAnswerScore,
         qt.AvgAnswerScore,
         qt.DaysToAccepted,
         -- activity-weighted quality metric: favors recent questions with many high scoring answers and short time to accept
         ((coalesce(qt.AvgAnswerScore,0) * least(1, greatest(0, 365.0 / nullif(date_part('day', now() - qt.QuestionCreated),0))))
           + coalesce(qt.MaxAnswerScore,0) * 0.7
           + coalesce(qt.QuestionScore,0) * 0.3
           + (case when qt.DaysToAccepted is not null then 5 / (1 + qt.DaysToAccepted) else 0 end)
         ) as QualityIndex,
         -- tag diversity: count distinct tags in related answers' bodies (heuristic explode)
         (
           select count(distinct t2) from (
             select lower(regexp_matches(a.Body, '(?<=<code>)[^<]{1,100}(?=</code>)' , 'g'))[1] as t2
             from Posts a
             where a.ParentId = qt.QuestionId and a.PostTypeId = 2 and a.Body is not null
             limit 50
           ) s where s.t2 is not null
         ) as CodeSnippetVariety
  from QuestionThreads qt
),

-- combine and produce final result with multiple joins, outer joins, set ops and complicated predicates
FinalSet as (
  select qc.QuestionId,
         left(trim(qc.Title), 200) as ShortTitle,
         qc.TopThreeTags,
         qc.QualityIndex,
         qc.CodeSnippetVariety,
         qc.AnswerCount,
         qc.DaysToAccepted,
         au.DisplayName as OwnerName,
         au.InfluenceScore as OwnerInfluence,
         uc.Questions2y,
         uc.Answers2y,
         uc.AvgAnswerNorm,
         coalesce(un.NeighborCount,0) as NeighborCount,
         dup.LinkCount as DuplicateLinks,
         ra.AnswerId as TopAnswerId,
         ra.Score as TopAnswerScore,
         ra.NormScore as TopAnswerNormScore,
         -- complex expression mixing nulls and booleans
         (case 
            when qc.QualityIndex is null then 'unknown'
            when qc.QualityIndex > 20 and qc.CodeSnippetVariety > 2 then 'excellent'
            when qc.QualityIndex > 10 or qc.CodeSnippetVariety >= 2 then 'good'
            when qc.QualityIndex > 0 then 'fair'
            else 'poor'
          end) as QualityBucket
  from QuestionComposite qc
  left join Users au on au.Id = qc.OwnerUserId
  left join UserContribs uc on uc.UserId = qc.OwnerUserId
  left join (
    select UserId, count(*) as NeighborCount from UserNeighbors group by UserId
  ) un on un.UserId = qc.OwnerUserId
  left join (
    select SourceId, sum(LinkCount) as LinkCount from DuplicateGraph where LinkType = 'Duplicate' group by SourceId
  ) dup on dup.SourceId = qc.QuestionId
  left join lateral (
    -- pick the top answer per question with additional correlated score boosting if author is active
    select ra.AnswerId, ra.Score, ra.NormScore
    from RankedAnswers ra
    left join ActiveUsers au2 on au2.Id = ra.OwnerUserId
    where ra.QuestionId = qc.QuestionId
    order by (ra.Score + coalesce(au2.InfluenceScore,0)/100.0) desc nulls last
    limit 1
  ) ra on true
)

-- final union to include recent high-activity users' favorite questions as fallback using set operator
select fs.*
from FinalSet fs
where fs.AnswerCount >= 1
  and fs.OwnerInfluence >= 50
  and fs.QualityIndex is not null
order by fs.QualityIndex desc nulls last, fs.CodeSnippetVariety desc
limit 200

union

select fs2.*
from FinalSet fs2
where fs2.OwnerInfluence < 50
  and fs2.AnswerCount >= 3
  and fs2.DaysToAccepted is null
  and array_length(fs2.TopThreeTags,1) >= 1
order by fs2.AnswerCount desc, fs2.OwnerInfluence desc
limit 50;