-- {"query": "1404.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1735} 
with RecursiveTagCounts as (
  select 
    t.Id as TagId,
    t.TagName,
    t.Count,
    -- recursive simulated rank over Count to amplify complexity
    dense_rank() over (order by t.Count desc) as OriginalRank
  from Tags t
),
AdjustedTagRanks as (
  select 
    TagId,
    TagName,
    Count,
    OriginalRank,
    OriginalRank + 
      case when Count > 1000 then 10 else 0 end as AdjustedRank,
    null::int as PrevTagId
  from RecursiveTagCounts
  union all
  select 
    r.TagId,
    r.TagName,
    r.Count,
    r.OriginalRank,
    r.AdjustedRank,
    a.TagId as PrevTagId
  from RecursiveTagCounts r
  join AdjustedTagRanks a on r.OriginalRank = a.OriginalRank - 1
  where a.TagName like 's%'
),
QualifiedPosts as (
  select p.Id,
         p.PostTypeId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.Title,
         coalesce(p.Tags, '') as Tags,
         u.Reputation as OwnerReputation,
         u.Location
  from Posts p
  left join Users u on p.OwnerUserId = u.Id
  where p.PostTypeId in (1, 2) -- Only Questions and Answers
    and (
      exists (
        select 1 from unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) t(tag) 
        where t.tag in (select TagName from Tags where Count > 1000)
      ) or p.Title ~* 'benchmark|performance|optimize'
    )
),
AggregatedVotes as (
  select 
    p.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount, 0) else 0 end) as TotalBounty
  from Votes v
  inner join Posts p on v.PostId = p.Id
  group by p.PostId
),
PostRankings as (
  select
    qp.Id,
    qp.PostTypeId,
    qp.Title,
    qp.CreationDate,
    qp.Score,
    qp.ViewCount,
    qp.OwnerUserId,
    qp.OwnerReputation,
    agg.UpVotes,
    agg.DownVotes,
    agg.TotalBounty,
    dense_rank() over (
      partition by qp.PostTypeId 
      order by qp.Score desc, qp.ViewCount desc NULLS LAST
    ) as PostDenseRank,
    row_number() over (
      partition by qp.OwnerUserId 
      order by qp.CreationDate desc
    ) as RecentPostNum
  from QualifiedPosts qp
  left join AggregatedVotes agg on agg.PostId = qp.Id
),
PostWithHistory as (
  select
    pr.*,
    ph.PostHistoryTypeId,
    -- complex JSON-like aggregate substring logic simulated by manually combining strings and embedded JSON keys showing recursion of edits critics in comments count in Posts second join etc
    concat(
      '[', string_agg(
          json_build_object(
            'HistoryType', ph.TH.Name,
            'Created', to_char(ph.CreationDate, 'YYYY-MM-DD"T"HH24:MI:SS'), 
            'User', coalesce(ph.UserDisplayName, 'Anon'), 
            'CommentSnippet', substr(coalesce(ph.Comment, 'No comment'),1,30)
          )::text, ', '
         ), ']') as PostHistJSON
  from PostRankings pr
  left join PostHistory ph on ph.PostId = pr.Id
  left join PostHistoryTypes th on th.Id = ph.PostHistoryTypeId
  group by pr.Id, pr.PostTypeId, pr.Title, pr.CreationDate, pr.Score, pr.ViewCount, pr.OwnerUserId, pr.OwnerReputation, pr.UpVotes, pr.DownVotes, pr.TotalBounty, pr.PostDenseRank, pr.RecentPostNum
),
CombinedFinal as (
  select 
    p.Id,
    p.Title,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    p.UpVotes,
    p.DownVotes,
    p.TotalBounty,
    count(distinct c.Id) as CommentCount,
    avg(ph.PostHistoryTypeId) filter (where ph.PostHistoryTypeId is not null) as AvgHistoryTypeId,
    string_agg(distinct COALESCE(b.Name,'') || '-' || cast(b.Class as varchar), ',' order by b.Date desc) as Badges,
    p.PostDenseRank,
    first_value(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as OwnerFirstPostDate,
    cast(row_number() over(partition by p.PostTypeId order by p.Score desc)::float / nullif(max(row_number() over (partition by p.PostTypeId order by p.Score desc)) over (), 0) as numeric(5,4)) as ScoreQuantileNormalized,
   (* Complex Case Linear Immun._
     Using two circumstance checks and arithmetic manual case-spans to observation intensity *)
    case
      when p.UpVotes > p.DownVotes and p.TotalBounty > 0 then round(log(p.UpVotes + 1)::numeric,3)
      when p.DownVotes >= p.UpVotes then round(pow(abs(p.DownVotes - p.UpVotes), 1.5), 3)
      else 0
    end as VoteInfluence
  from PostWithHistory p
  left join Users u on u.Id = p.OwnerUserId
  left join Comments c on c.PostId = p.Id
  left join PostHistory ph on ph.PostId = p.Id
  left join Badges b on b.UserId = p.OwnerUserId
  where (p.Score >= 5 or p.UpVotes >= 5) and (p.OwnerReputation >= 1000 or p.OwnerUserId is null)
  group by p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, u.Reputation, p.UpVotes, p.DownVotes, p.TotalBounty, p.PostDenseRank
),
TopQuestionDuplicates as (
  select pl.PostId, count(pl.RelatedPostId) as DupCount
  from PostLinks pl
  inner join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
  inner join Posts p on pl.PostId = p.Id and p.PostTypeId = 1
  group by pl.PostId
)
select
  cf.Id,
  cf.Title,
  cf.PostTypeId,
  pt.Name as PostTypeName,
  cf.Score,
  cf.ViewCount,
  cf.DisplayName as Owner,
  cf.Reputation as OwnerRep,
  cf.UpVotes,
  cf.DownVotes,
  cf.TotalBounty,
  cf.Badges,
  cf.CommentCount,
  cf.AvgHistoryTypeId,
  cf.PostDenseRank,
  cf.OwnerFirstPostDate,
  cf.ScoreQuantileNormalized,
  cf.VoteInfluence,
  coalesce(td.DupCount, 0) as DuplicateCount,
  case when cf.ViewCount > 0 then round(cast(cf.Score as numeric)/cf.ViewCount,5) else null end as ScoreViewRatio,
  lower(cf.Title) like '%performance%' as HasPerformanceKeyword,
  cf.VoteInfluence * cf.ScoreQuantileNormalized as ComplexScoreMetric
from CombinedFinal cf
left join PostTypes pt on pt.Id = cf.PostTypeId
left join TopQuestionDuplicates td on td.PostId = cf.Id
where (cf.PostTypeId = 1 and cf.Score >= 50) or (cf.PostTypeId = 2 and cf.UpVotes >= 10)
order by ComplexScoreMetric desc nulls last, cf.Score desc, cf.ViewCount desc
limit 50;