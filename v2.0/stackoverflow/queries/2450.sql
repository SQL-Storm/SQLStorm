-- {"query": "2450.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1577}
with RankedPosts as (
  select
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.Title,
    p.Tags,
    row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as rn,
    rank() over (partition by p.PostTypeId order by p.ViewCount desc) as view_rank,
    case
      when p.Tags is null or length(trim(p.Tags)) = 0 then NULL
      else string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')
    end as tag_array
  from Posts p
),
UserBadgeStats as (
  select
    b.UserId,
    count(case when b.Class = 1 then 1 end) as gold_badges,
    count(case when b.Class = 2 then 1 end) as silver_badges,
    count(case when b.Class = 3 then 1 end) as bronze_badges,
    max(case when b.TagBased then 1 else 0 end) = 1 as has_tagbased_badges
  from Badges b
  group by b.UserId
),
QuestionCloseInfo as (
  select
    ph.PostId,
    crt.Name as CloseReason,
    ph.CreationDate as CloseDate
  from PostHistory ph
  inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
  where ph.PostHistoryTypeId = 10
    and ph.PostId in (select Id from Posts where PostTypeId = 1)
),
LatestUserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    max(ph.CreationDate) as LastEditDate,
    count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
    count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join PostHistory ph on ph.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
UserPerformance as (
  select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(ub.gold_badges,0) as GoldBadges,
    coalesce(ub.silver_badges,0) as SilverBadges,
    coalesce(ub.bronze_badges,0) as BronzeBadges,
    u.QuestionCount,
    u.AnswerCount,
    u.LastEditDate,
    case when ub.has_tagbased_badges then 'Yes' else 'No' end as TagBasedBadges,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    p.Id as TopQuestionId,
    p.Score as TopQuestionScore,
    p.ViewCount as TopQuestionViews,
    p.Title as TopQuestionTitle,
    array_to_string(p.tag_array, ', ') as TopQuestionTags,
    ci.CloseReason,
    ci.CloseDate,
    row_number() over (partition by u.UserId order by p.Score desc) as top_question_rank
  from LatestUserActivity u
  left join UserBadgeStats ub on ub.UserId = u.UserId
  left join RankedPosts p on p.OwnerUserId = u.UserId and p.PostTypeId = 1 and p.rn = 1
  left join QuestionCloseInfo ci on ci.PostId = p.Id
),
VotesSummary as (
  select
    v.PostId,
    sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
    sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
    sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
    sum(case when vt.Name = 'BountyStart' then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty,
    count(*) as TotalVotes
  from Votes v
  inner join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
PostLinksWithDetails as (
  select
    pl.Id,
    pl.CreationDate,
    pl.PostId,
    pl.RelatedPostId,
    lt.Name as LinkTypeName,
    p1.Title as PostTitle,
    p2.Title as RelatedPostTitle,
    p1.Score as PostScore,
    p2.Score as RelatedPostScore
  from PostLinks pl
  inner join LinkTypes lt on lt.Id = pl.LinkTypeId
  left join Posts p1 on p1.Id = pl.PostId
  left join Posts p2 on p2.Id = pl.RelatedPostId
),
UserCommentCounts as (
  select
    c.UserId,
    count(*) as CommentCount,
    avg(length(c.Text)) as AvgCommentLength,
    count(distinct c.PostId) as DistinctPostsCommented
  from Comments c
  group by c.UserId
)

select 
  up.UserId,
  up.DisplayName,
  up.Reputation,
  up.GoldBadges,
  up.SilverBadges,
  up.BronzeBadges,
  up.TagBasedBadges,
  up.QuestionCount,
  up.AnswerCount,
  up.LastEditDate,
  up.Location,
  up.Views,
  up.UpVotes,
  up.DownVotes,
  up.TopQuestionId,
  up.TopQuestionScore,
  up.TopQuestionViews,
  substring(up.TopQuestionTitle from 1 for 100) as TopQuestionTitle,
  up.TopQuestionTags,
  up.CloseReason,
  up.CloseDate,
  coalesce(uc.CommentCount, 0) as UserComments,
  coalesce(uc.AvgCommentLength, 0) as AverageCommentLength,
  coalesce(uc.DistinctPostsCommented, 0) as UniquePostsCommented,
  vl.LinkTypeName,
  vl.PostTitle,
  vl.RelatedPostTitle,
  vl.PostScore,
  vl.RelatedPostScore,
  vs.UpVotes as PostUpVotes,
  vs.DownVotes as PostDownVotes,
  vs.Favorites as PostFavorites,
  vs.TotalBounty,
  rank() over (order by up.Reputation desc, up.GoldBadges desc, up.SilverBadges desc) as OverallUserRank
from UserPerformance up
left join UserCommentCounts uc on uc.UserId = up.UserId
left join PostLinksWithDetails vl on vl.PostId = up.TopQuestionId
left join VotesSummary vs on vs.PostId = up.TopQuestionId
where up.UserId in (
  select distinct OwnerUserId from Posts where PostTypeId = 1 and CreationDate between date '2020-01-01' and date '2022-12-31'
)
and (up.GoldBadges + up.SilverBadges + up.BronzeBadges) > 5
and (up.QuestionCount > 10 or up.AnswerCount > 20)
order by OverallUserRank
limit 100;