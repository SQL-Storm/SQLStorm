with recursive RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, 0 as Level, t.ExcerptPostId, t.WikiPostId
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    union all
    select t2.Id, t2.TagName, t2.Count, r.Level + 1, t2.ExcerptPostId, t2.WikiPostId
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count <= r.Count
    where t2.IsModeratorOnly = false and t2.IsRequired = false and r.Level < 2
),
PostWithAcceptedAnswer AS (
    select p.Id, p.PostTypeId, p.AcceptedAnswerId, p.CreationDate, 
           p.Score, p.ViewCount, p.Title, p.Tags,
           u.DisplayName as OwnerName,
           coalesce(p.FavoriteCount,0) as FavoriteCount,
           ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) as RankByScoreView,
           p.OwnerUserId
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
AnswerStatsWithVotes AS (
    select a.ParentId as QuestionId,
           count(*) as TotalAnswers,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
           avg(a.Score) as AvgAnswerScore
    from Posts a
    left join Votes v on v.PostId = a.Id and v.VoteTypeId in (2,3)
    where a.PostTypeId = 2
    group by a.ParentId
),
PostHistoryAggregates AS (
    select ph.PostId,
           max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as ClosedDate,
           max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as ReopenedDate,
           count(distinct case when ph.PostHistoryTypeId = 52 then ph.Id end) as HotQuestionCount,
           count(distinct ph.UserId) as DistinctEditors
    from PostHistory ph
    group by ph.PostId
),
UserBadgeComplexity as (
    select u.Id as UserId,
           count(distinct b.Id) as BadgeCount,
           sum(case when b.Class = 1 then 3 when b.Class = 2 then 2 else 1 end) as BadgeWeight,
           bool_or(b.TagBased = true) as HasTagBadges,
           count(distinct b.Name) filter (where b.Class = 1) as GoldBadgeNamesCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
AllPostComments as (
    select c.PostId, 
           count(*) as CommentCount,
           string_agg(distinct substr(c.Text, 1, 10), ', ') as SampleCommentTexts
    from Comments c
    group by c.PostId
),
PostLinkComplex as (
    select pl.PostId,
           count(*) as OutgoingLinksCount,
           count(distinct pl.RelatedPostId) as DistinctLinkedPosts,
           sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinks,
           bool_or(pl.RelatedPostId in (
                select p2.Id from Posts p2 where p2.Score > 1000 and p2.PostTypeId = 1)
           ) as LinksToPopularQuestion
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select p.Id, p.PostTypeId, p.Title, p.OwnerName,
       p.Score, p.ViewCount, p.FavoriteCount,
       psa.TotalAnswers, psa.TotalUpVotes, psa.TotalDownVotes, psa.AvgAnswerScore,
       pha.ClosedDate, pha.ReopenedDate, pha.HotQuestionCount, pha.DistinctEditors,
       ub.BadgeCount, ub.BadgeWeight, ub.HasTagBadges, ub.GoldBadgeNamesCount,
       plc.OutgoingLinksCount, plc.DistinctLinkedPosts, plc.DuplicateLinks, plc.LinksToPopularQuestion,
       ac.CommentCount, ac.SampleCommentTexts,
       (
        select string_agg(distinct rth2.TagName, ' > ')
        from RecursiveTagHierarchy rth2
        where rth2.TagName = any(string_to_array(substring(coalesce(p.Tags, ''), 2, length(coalesce(p.Tags, '')) - 2), '><'))
          and rth2.Level = 0
       ) as TopLevelTags,
       (
        select string_agg(distinct rth3.TagName, ' > ')
        from RecursiveTagHierarchy rth3
        where rth3.TagName = any(string_to_array(substring(coalesce(p.Tags, ''), 2, length(coalesce(p.Tags, '')) - 2), '><'))
          and rth3.Level = 1
       ) as SecondaryLevelTags,
       dense_rank() over (order by p.Score desc) as GlobalRank,
       case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
       case 
          when (p.Score > 100 and coalesce(psa.TotalAnswers,0) > 10 and coalesce(ub.BadgeWeight,0) > 10) then 'High Impact'
          when (p.Score between 50 and 100 or coalesce(psa.TotalAnswers,0) between 5 and 10) then 'Medium Impact'
          else 'Low Impact'
       end as ImpactCategory
from PostWithAcceptedAnswer p
left join AnswerStatsWithVotes psa on psa.QuestionId = p.Id
left join PostHistoryAggregates pha on pha.PostId = p.Id
left join UserBadgeComplexity ub on ub.UserId = p.OwnerUserId
left join PostLinkComplex plc on plc.PostId = p.Id
left join AllPostComments ac on ac.PostId = p.Id
where p.RankByScoreView <= 100
order by p.Score desc, p.ViewCount desc
limit 50;