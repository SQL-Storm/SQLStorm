-- {"query": "2871.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1321} 
with RecursivePosts as (
  select p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.OwnerUserId, 0 as Level
  from Posts p
  where p.PostTypeId = 1 -- questions only
    and p.CreationDate >= now() - interval '1 year'
  union all
  select a.Id, a.PostTypeId, a.CreationDate, a.Score, a.ViewCount, a.Title, a.OwnerUserId, rp.Level + 1
  from Posts a
  join RecursivePosts rp on a.ParentId = rp.Id
  where a.PostTypeId = 2 -- answers
),
PostScoreWindow as (
  select
    rp.Id as PostId,
    rp.Title,
    rp.CreationDate,
    rp.Level,
    rp.Score,
    rp.ViewCount,
    u.DisplayName as OwnerName,
    coalesce(badge_counts.GoldBadges,0) as GoldBadges,
    coalesce(badge_counts.SilverBadges,0) as SilverBadges,
    coalesce(badge_counts.BronzeBadges,0) as BronzeBadges,
    row_number() over (partition by rp.Level order by rp.Score desc, rp.ViewCount desc) as RankByScore,
    avg(rp.Score) over (partition by rp.Level) as AvgScorePerLevel,
    count(*) over (partition by rp.Level) as PostsPerLevel
  from RecursivePosts rp
  left join Users u on u.Id = rp.OwnerUserId
  left join (
    select UserId,
      sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
      sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
      sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
  ) badge_counts on badge_counts.UserId = rp.OwnerUserId
),
TopScoringPosts as (
  select PostId, Title, Level, Score, ViewCount, OwnerName, GoldBadges, SilverBadges, BronzeBadges,
         RankByScore, AvgScorePerLevel, PostsPerLevel
  from PostScoreWindow
  where RankByScore <= 10
),
PostsWithCloseReasons as (
  select ph.PostId,
    string_agg(distinct crt.Name, ', ') as CloseReasons
  from PostHistory ph
  join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
  where ph.PostHistoryTypeId = 10 -- Post Closed
  group by ph.PostId
),
QuestionTagAnalysis as (
  select
    p.Id as QuestionId,
    p.Tags,
    array_remove(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'), NULL) as TagArray
  from Posts p
  where p.PostTypeId = 1
),
TagUserActivity as (
  select
    nta.QuestionId,
    unnest(nta.TagArray) as Tag,
    count(distinct u.Id) as UniqueAnswerers,
    coalesce(sum(a.Score),0) as TotalAnswerScore
  from QuestionTagAnalysis nta
  join Posts a on a.ParentId = nta.QuestionId and a.PostTypeId = 2
  join Users u on u.Id = a.OwnerUserId
  group by nta.QuestionId, Tag
),
HighImpactTags as (
  select Tag, sum(TotalAnswerScore) as TagScoreSum, avg(UniqueAnswerers) as AvgAnswerers
  from TagUserActivity
  group by Tag
  having sum(TotalAnswerScore) > 1000 and avg(UniqueAnswerers) > 2
),
ClosedTopPostsWithTags as (
  select tsp.PostId, tsp.Title, tsp.Level, tsp.Score, tsp.ViewCount, tsp.OwnerName, tsp.GoldBadges,
         tsp.SilverBadges, tsp.BronzeBadges, pcrt.CloseReasons,
         (select count(*) from Comments c where c.PostId = tsp.PostId) as CommentCount,
         (select count(*) from Votes v where v.PostId = tsp.PostId and v.VoteTypeId = 2) as UpVotes,
         (select count(*) from Votes v where v.PostId = tsp.PostId and v.VoteTypeId = 3) as DownVotes,
         regexp_replace(t.Tags, '[<>]', ' ', 'g') as TagStrings
  from TopScoringPosts tsp
  left join PostsWithCloseReasons pcrt on pcrt.PostId = tsp.PostId
  left join Posts t on t.Id = tsp.PostId
  where tsp.Level = 0
),
FinalResult as (
  select
    ctp.PostId,
    ctp.Title,
    ctp.Score,
    ctp.ViewCount,
    ctp.CommentCount,
    ctp.CloseReasons,
    ctp.TagStrings,
    ctp.OwnerName,
    ctp.GoldBadges, ctp.SilverBadges, ctp.BronzeBadges,
    ctp.UpVotes,
    ctp.DownVotes,
    case 
      when ctp.ViewCount > 0 then round(cast(ctp.Score as numeric) / ctp.ViewCount, 4)
      else null
    end as ScorePerView,
    rank() over (order by ctp.Score desc, ctp.ViewCount desc) as OverallRank
  from ClosedTopPostsWithTags ctp
  where (ctp.CloseReasons is null or char_length(ctp.CloseReasons) = 0)
  union
  select
    0 as PostId,
    'Summary for High Impact Tags' as Title,
    null as Score,
    null as ViewCount,
    null as CommentCount,
    null as CloseReasons,
    string_agg(distinct Hit.Tag, ', ') as TagStrings,
    null as OwnerName,
    null as GoldBadges,
    null as SilverBadges,
    null as BronzeBadges,
    null as UpVotes,
    null as DownVotes,
    null as ScorePerView,
    null as OverallRank
  from HighImpactTags Hit
)
select * from FinalResult
order by OverallRank nulls last, PostId;