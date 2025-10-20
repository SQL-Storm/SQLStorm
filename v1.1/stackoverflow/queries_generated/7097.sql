-- {"query": "7097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2410} 
with
-- recent activity per post including owner info and tag parsing
PostBase as (
  select
    p.Id,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.OwnerUserId,
    coalesce(u.DisplayName, p.OwnerDisplayName, '<anon>') as OwnerName,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    -- derive tag array by stripping <> wrapper; tolerant to nulls
    case when p.Tags is null then array[]::varchar[] else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as TagArray
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.CreationDate >= (current_timestamp - interval '5 years') -- restrict to recent for benchmarking
),
-- compute per-post aggregated vote stats using conditional aggregation
PostVotes as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes,
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    count(*) filter (where v.VoteTypeId = 5) as Favorites,
    count(*) filter (where v.VoteTypeId in (8,9) and coalesce(v.BountyAmount,0)>0) as Bounties,
    sum(coalesce(v.BountyAmount,0)) filter (where v.VoteTypeId in (8,9)) as BountySum,
    max(v.CreationDate) as LastVoteDate
  from Votes v
  group by v.PostId
),
-- recent edits and history-based metrics with correlated subquery for latest meaningful edit
PostHistoryAgg as (
  select
    ph.PostId,
    count(*) as HistoryCount,
    count(*) filter (where ph.PostHistoryTypeId in (5,6,24)) as EditCount,
    max(ph.CreationDate) as LastHistoryDate,
    -- correlated: find the user who made the last non-null UserId history change
    (select ph2.UserId from PostHistory ph2 where ph2.PostId = ph.PostId and ph2.UserId is not null order by ph2.CreationDate desc limit 1) as LastEditorUserId,
    (select ph3.Comment from PostHistory ph3 where ph3.PostId = ph.PostId and ph3.Comment is not null and length(ph3.Comment) > 0 order by ph3.CreationDate desc limit 1) as LastHistoryComment
  from PostHistory ph
  group by ph.PostId
),
-- tag popularity snapshot: explode tags and count occurrences (CTE used by multiple downstreams)
ExplodedTags as (
  select
    pb.Id as PostId,
    unnest(pb.TagArray) as Tag
  from PostBase pb
  where pb.TagArray is not null and array_length(pb.TagArray,1) > 0
),
TagStats as (
  select
    Tag,
    count(*) as QuestionCount,
    avg(pb.Score) as AvgScore,
    percentile_cont(0.5) within group (order by pb.Score) as MedianScore
  from ExplodedTags et
  join PostBase pb on pb.Id = et.PostId and pb.PostTypeId = 1
  group by Tag
  order by QuestionCount desc
  limit 200
),
-- compute per-user contributions and temporal patterns
UserActivity as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    count(distinct p.Id) filter (where p.PostTypeId = 1) as Questions,
    count(distinct p.Id) filter (where p.PostTypeId = 2) as Answers,
    count(distinct c.Id) as Comments,
    coalesce(sum(vt.UpVotes),0) as ReceivedUpVotes,
    coalesce(sum(vt.DownVotes),0) as ReceivedDownVotes,
    -- window function: rank users by combined contributions
    row_number() over (order by (count(distinct p.Id) filter (where p.PostTypeId in (1,2)) + coalesce(sum(vt.UpVotes),0)/100.0) desc) as ContributionRank,
    -- last seen
    max(p.LastActivityDate) as LastPostActivity,
    u.CreationDate
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join (
    select PostId, count(*) filter (where VoteTypeId = 2) as UpVotes, count(*) filter (where VoteTypeId = 3) as DownVotes
    from Votes
    group by PostId
  ) vt on vt.PostId = p.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
-- identify questions with controversial score (many opposite votes) using existence of both up and down
ControversialQuestions as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    coalesce(p.Score,0) as Score,
    pv.UpVotes,
    pv.DownVotes,
    case when pv.UpVotes >= 5 and pv.DownVotes >= 5 then true else false end as IsControversial,
    greatest(coalesce(pv.UpVotes,0), coalesce(pv.DownVotes,0)) as MaxExtremeVotes
  from PostBase p
  left join PostVotes pv on pv.PostId = p.Id
  where p.PostTypeId = 1
),
-- assemble answer quality assessment using window functions and correlated subqueries for accepted answer influence
AnswerQuality as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.CreationDate,
    a.Score,
    pv.UpVotes,
    pv.DownVotes,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as RankByScore,
    -- fraction of question's view count per answer (approx)
    case when q.ViewCount > 0 then round(100.0 * a.Score::numeric / nullif(q.ViewCount,0),4) else 0 end as ScorePctOfViews,
    -- is accepted?
    case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted,
    -- age delta between question and answer
    extract(epoch from (a.CreationDate - q.CreationDate))/86400.0 as DaysToAnswer,
    -- correlated: number of comments on this answer
    (select count(*) from Comments c where c.PostId = a.Id) as CommentCount
  from Posts a
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  left join PostVotes pv on pv.PostId = a.Id
  where a.PostTypeId = 2
),
-- heavy query combining many constructs: selects top N questions with composite score and enriches with tag and user metrics
RankedQuestions as (
  select
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.OwnerName,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    coalesce(pv.UpVotes,0) as UpVotes,
    coalesce(pv.DownVotes,0) as DownVotes,
    coalesce(phag.EditCount,0) as EditCount,
    coalesce(ta.QuestionCount,0) as TagPopularity,
    us.ContributionRank as OwnerRank,
    -- composite metric: favor recent, high score, many answers, high tag popularity, penalize controversies
    (
      (q.Score * 3.0)
      + log(1 + q.ViewCount)
      + (coalesce(q.AnswerCount,0) * 2.5)
      + (coalesce(ta.QuestionCount,0) * 1.2)
      - (case when coalesce(cq.IsControversial,false) then least(20, coalesce(cq.MaxExtremeVotes,0)) else 0 end)
      + (coalesce(phag.EditCount,0) * 0.5)
      - (extract(epoch from (current_timestamp - q.CreationDate))/86400.0) * 0.01
    ) as CompositeScore,
    -- sample of first three tags concatenated, with null-handling
    (case when q.TagArray is null or array_length(q.TagArray,1) = 0 then '<no-tag>' else array_to_string(q.TagArray[1:3], ',') end) as TopTags,
    -- flag for stale unanswered popular questions
    case when q.AnswerCount = 0 and q.ViewCount > 1000 and q.Score >= 0 and q.CreationDate < current_timestamp - interval '180 days' then 1 else 0 end as HotUnanswered
  from PostBase q
  left join PostVotes pv on pv.PostId = q.Id
  left join PostHistoryAgg phag on phag.PostId = q.Id
  left join LATERAL (
    select Tag, QuestionCount from TagStats ts
    where ts.Tag = (case when q.TagArray is null then null else q.TagArray[1] end)
    limit 1
  ) ta on true
  left join UserActivity us on us.Id = q.OwnerUserId
  left join ControversialQuestions cq on cq.Id = q.Id
  where q.PostTypeId = 1
)
select
  rq.*,
  -- join in aggregate answer metrics: avg answer score, median answer age, accepted answer bonus
  aq.AnswerCount,
  aq.AvgAnswerScore,
  aq.MedianDaysToAnswer,
  aq.AcceptedAnswerScore,
  -- snippet of last history comment (string manipulation)
  left(coalesce(ph.LastHistoryComment, 'no history comment'), 200) as RecentHistoryNote,
  -- badge influence: number of gold badges owner has (if any)
  coalesce(b.GoldBadges,0) as OwnerGoldBadges
from RankedQuestions rq
left join (
  select
    a.QuestionId,
    count(*) as AnswerCount,
    avg(a.Score) as AvgAnswerScore,
    percentile_cont(0.5) within group (order by a.DaysToAnswer) as MedianDaysToAnswer,
    max(case when a.IsAccepted = 1 then a.Score else null end) as AcceptedAnswerScore
  from AnswerQuality a
  group by a.QuestionId
) aq on aq.QuestionId = rq.Id
left join PostHistoryAgg ph on ph.PostId = rq.Id
left join (
  select
    b.UserId,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges
  from Badges b
  group by b.UserId
) b on b.UserId = rq.OwnerUserId
where rq.CompositeScore is not null
order by rq.CompositeScore desc nulls last, rq.UpVotes desc
limit 250;