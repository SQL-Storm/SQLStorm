-- {"query": "2420.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1604} 
with RecursivePosts as (
  select p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
         p.OwnerUserId, p.Title, p.AnswerCount,
         cast(0 as int) as Depth
  from Posts p
  where p.PostTypeId = 1 -- questions only
  union all
  select c.Id, c.PostTypeId, c.AcceptedAnswerId, c.ParentId, c.CreationDate, c.Score, c.ViewCount, c.Tags,
         c.OwnerUserId, c.Title, c.AnswerCount,
         rp.Depth + 1
  from Posts c
  join RecursivePosts rp on c.ParentId = rp.Id
  where c.PostTypeId = 2 -- answers only
),
BadgeCounts as (
  select UserId,
         sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
         sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
         sum(case when Class = 3 then 1 else 0 end) as BronzeBadges,
         count(*) as TotalBadges
  from Badges
  group by UserId
),
UserReputationWindow as (
  select Id, Reputation,
         rank() over (order by Reputation desc) as RepRank,
         percent_rank() over (order by Reputation desc) as RepPercentRank
  from Users
),
PostScoreWindows as (
  select p.Id, p.PostTypeId, p.Score,
         row_number() over (partition by p.PostTypeId order by p.Score desc, p.CreationDate) as ScoreRank,
         avg(p.Score) over (partition by p.PostTypeId) as AvgScorePerType,
         stddev_pop(p.Score) over (partition by p.PostTypeId) as StdDevScorePerType
  from Posts p
  where p.Score is not null
),
QuestionsWithCloseReasons as (
  select ph.PostId,
         max(case when ph.PostHistoryTypeId = 10 then crt.Name else null end) as CloseReasonName,
         max(ph.CreationDate) as CloseDate
  from PostHistory ph
  left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
),
TopCommentsPerPost as (
  select c.PostId, c.Id as CommentId, c.Score, c.CreationDate, c.UserId, c.UserDisplayName,
         row_number() over (partition by c.PostId order by c.Score desc nulls last, c.CreationDate asc) as CommentRank
  from Comments c
),
FilteredComments as (
  select * from TopCommentsPerPost where CommentRank <= 3
),
AllPostsAndOwners as (
  select p.Id as PostId, p.PostTypeId, p.Title, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.OwnerUserId,
         u.DisplayName as OwnerName, u.Reputation as OwnerReputation,
         bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges, bc.TotalBadges,
         qr.CloseReasonName, qr.CloseDate
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  left join BadgeCounts bc on bc.UserId = u.Id
  left join QuestionsWithCloseReasons qr on qr.PostId = p.Id
)
select
  ap.PostId,
  ap.PostTypeId,
  case when ap.PostTypeId = 1 then 'Question'
       when ap.PostTypeId = 2 then 'Answer'
       else 'Other' end as PostTypeName,
  ap.Title,
  -- extract first tag from Tags column (which is format like '<tag1><tag2><tag3>')
  nullif(substring(ap.Tags from '<([^>]+)>'), '') as FirstTag,
  ap.Score,
  ap.ViewCount,
  ap.AnswerCount,
  ap.CreationDate,
  ap.OwnerUserId,
  coalesce(ap.OwnerName, 'Unknown') as OwnerName,
  ap.OwnerReputation,
  ap.GoldBadges,
  ap.SilverBadges,
  ap.BronzeBadges,
  ap.TotalBadges,
  ap.CloseReasonName,
  ap.CloseDate,
  -- Average score of posts by owner as correlated scalar subquery with NULL logic
  (
    select avg(p2.Score)
    from Posts p2
    where p2.OwnerUserId = ap.OwnerUserId and p2.Score is not null
  ) as AvgOwnerPostScore,
  -- Count of distinct tags on question as length of tags array if question
  case when ap.PostTypeId = 1 and ap.Tags is not null then array_length(string_to_array(substring(ap.Tags from 2 for char_length(ap.Tags) - 2), '><'), 1) else 0 end as TagCount,
  -- Window function: Rank of this post's score within its post type
  psw.ScoreRank,
  -- Calculate text length of Title ignoring NULL and trimming
  length(trim(coalesce(ap.Title, ''))) as TitleLength,
  -- String expression: concatenate OwnerName and FirstTag with delimiter, handling NULLs
  concat_ws(' | ', ap.OwnerName, nullif(substring(ap.Tags from '<([^>]+)>'), '')) as OwnerAndTag,
  -- Coalesce between answers counts or default zero
  coalesce(ap.AnswerCount, 0) as SafeAnswerCount,
  -- Filtering in outer join: pick top 3 comments with highest score for this post
  array_agg(json_build_object('CommentId', fc.CommentId, 'Score', fc.Score, 'UserDisplayName', fc.UserDisplayName) order by fc.Score desc nulls last, fc.CreationDate asc) filter (where fc.CommentId is not null) as TopComments,
  -- Correlated EXISTS subquery: whether post received any bounty start votes
  exists (
    select 1 from Votes v where v.PostId = ap.PostId and v.VoteTypeId = 8
  ) as HasBountyStart,
  -- Complex calculation: score normalized by (owner reputation + 1000) sqrt transformed, NULL safe
  case when ap.OwnerReputation is not null and ap.OwnerReputation >= 0 and ap.Score is not null then ap.Score / sqrt(ap.OwnerReputation + 1000.0) else null end as NormScore,
  -- NULL-safe coalesce with boolean logic: does user have any gold badge or reputation above 10000
  (coalesce(ap.GoldBadges, 0) > 0) or (coalesce(ap.OwnerReputation, 0) > 10000) as IsHighRepOrGoldBadgeUser
from AllPostsAndOwners ap
left join PostScoreWindows psw on psw.Id = ap.PostId
left join FilteredComments fc on fc.PostId = ap.PostId and fc.CommentRank <= 3
group by ap.PostId, ap.PostTypeId, ap.Title, ap.Tags, ap.Score, ap.ViewCount, ap.AnswerCount, ap.CreationDate, ap.OwnerUserId,
         ap.OwnerName, ap.OwnerReputation, ap.GoldBadges, ap.SilverBadges, ap.BronzeBadges, ap.TotalBadges,
         ap.CloseReasonName, ap.CloseDate, psw.ScoreRank
order by ap.CreationDate desc, ap.Score desc
limit 100;