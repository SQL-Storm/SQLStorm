with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    where p.PostTypeId in (1, 2)
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtype on ph.PostHistoryTypeId = chtype.Id
    join CloseReasonTypes cht on cast(ph.Comment as integer) = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        sum(p.Score) as TotalPostScore,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        case when max(p.CreationDate) is not null and min(p.CreationDate) is not null then
            extract(epoch from (max(p.CreationDate) - min(p.CreationDate))) / 86400.0
        else null end as ActiveDays
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswererName,
        row_number() over (partition by q.Id order by a.Score desc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(ph.CreationDate) as LastActivity,
        count(ph.Id) filter (where ph.PostHistoryTypeId in (10, 11)) as CloseReopenEvents,
        count(ph.Id) filter (where ph.PostHistoryTypeId = 24) as SuggestedEdits,
        count(ph.Id) filter (where ph.PostHistoryTypeId = 50) as CommunityBumps
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    rtc.TagRank,
    rtc.TagName,
    rtc.Count as TagUsageCount,
    rtc.AnswerCount,
    rtc.ViewCount,
    rtc.Score as TagExcerptScore,
    ubs.DisplayName as TopUserWithBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    ubs.LastBadgeDate,
    uas.TotalPosts,
    uas.TotalComments,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    uas.TotalPostScore,
    uas.ActiveDays,
    qwa.QuestionId,
    qwa.Title as QuestionTitle,
    qwa.Tags as QuestionTags,
    qwa.QuestionScore,
    qwa.ViewCount as QuestionViewCount,
    qwa.AnswerId,
    qwa.AnswerScore,
    qwa.AnswerCreationDate,
    qwa.AnswererName,
    dl.PostId as DuplicatePostId,
    dl.RelatedPostId as DuplicateRelatedPostId,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostTitle as DuplicateRelatedPostTitle,
    dl.LinkTypeName as DuplicateLinkType,
    urr.Reputation,
    urr.ReputationRank,
    ura.LastActivity,
    ura.CloseReopenEvents,
    ura.SuggestedEdits,
    ura.CommunityBumps
from RecursiveTagCounts rtc
left join UserBadgeStats ubs on ubs.UserId = (
    select ub.UserId from UserBadgeStats ub
    where ub.GoldBadges > 0
    order by ub.GoldBadges desc, ub.SilverBadges desc
    limit 1
)
left join UserActivitySummary uas on uas.Id = ubs.UserId
left join TopQuestionsWithAnswers qwa on qwa.QuestionId = rtc.Id and qwa.AnswerRank = 1
left join DuplicateLinks dl on dl.PostId = qwa.QuestionId
left join UserReputationRank urr on urr.Id = uas.Id
left join UserRecentActivity ura on ura.UserId = uas.Id
where rtc.TagRank <= 10
order by rtc.TagRank, qwa.AnswerScore desc;