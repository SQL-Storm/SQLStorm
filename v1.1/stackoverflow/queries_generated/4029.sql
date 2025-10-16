-- {"query": "4029.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1575} 
with RecursiveBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Class

    union all

    select
        rbc.UserId,
        rbc.DisplayName,
        case when rbc.Class is null then 1 else rbc.Class + 1 end,
        0
    from RecursiveBadgeCounts rbc
    where rbc.Class is null or rbc.Class < 3
),
TopUsersByBadge as (
    select
        UserId,
        DisplayName,
        max(BadgeCount) filter (where Class = 1) as GoldBadges,
        max(BadgeCount) filter (where Class = 2) as SilverBadges,
        max(BadgeCount) filter (where Class = 3) as BronzeBadges
    from RecursiveBadgeCounts
    group by UserId, DisplayName
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        sum(case when p.AcceptedAnswerId = p.Id then 1 else 0 end) as TimesAccepted
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionAnswerDetails as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
FilteredTopAnswers as (
    select
        QuestionId,
        Title,
        OwnerUserId,
        AnswerId,
        AnswerCreation,
        AnswerScore,
        AnswerOwnerUserId
    from QuestionAnswerDetails
    where AnswerRank = 1
),
UserAnswerAccepts as (
    select
        u.Id as UserId,
        count(*) as AcceptedAnswerCount
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 2
    where exists(
        select 1 from Posts q where q.AcceptedAnswerId = p.Id and q.PostTypeId = 1
    )
    group by u.Id
),
ComplexPostTags as (
    select
        p.Id as PostId,
        p.Title,
        p.Tags,
        unnest(string_to_array(trim(both '<>' from coalesce(p.Tags, '')), '><')) as SingleTag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags <> ''
),
TagCounts as (
    select
        t.TagName,
        count(distinct cp.PostId) as QuestionCount,
        sum(p.ViewCount) as TotalViews,
        avg(p.Score) as AvgScore
    from Tags t
    left join ComplexPostTags cp on cp.SingleTag = t.TagName
    left join Posts p on p.Id = cp.PostId
    group by t.TagName
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(p.LastActivityDate) as LastPostActivity,
        max(c.CreationDate) as LastCommentDate,
        greatest(max(p.LastActivityDate), max(c.CreationDate)) as LastActivityOverall
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
VotesSummary as (
    select
        p.Id as PostId,
        p.PostTypeId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as Favorites,
        sum(coalesce(v.BountyAmount, 0)) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId
),
PostLinkSummary as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        count(*) over (partition by pl.PostId, pl.LinkTypeId) as LinkCountPerType
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
FinalResult as (
    select
        u.Id as UserId,
        u.DisplayName,
        up.QuestionsAsked,
        up.AnswersGiven,
        up.AvgAnswerScore,
        up.MaxAnswerScore,
        coalesce(uba.AcceptedAnswerCount, 0) as AcceptedAnswers,
        tb.GoldBadges,
        tb.SilverBadges,
        tb.BronzeBadges,
        ua.LastActivityOverall,
        tc.TagName as FavoriteTag,
        tc.QuestionCount as TagQuestionCount,
        tc.TotalViews as TagTotalViews,
        tc.AvgScore as TagAvgScore,
        vsm.UpVotes as LastPostUpVotes,
        vsm.DownVotes as LastPostDownVotes,
        vsm.Favorites as LastPostFavorites,
        vsm.TotalBounty as LastPostBounty
    from Users u
    left join UserPostStats up on up.UserId = u.Id
    left join UserAnswerAccepts uba on uba.UserId = u.Id
    left join TopUsersByBadge tb on tb.UserId = u.Id
    left join UserRecentActivity ua on ua.UserId = u.Id
    left join Lateral (
        select t.TagName, t.QuestionCount, t.TotalViews, t.AvgScore
        from TagCounts t
        join ComplexPostTags cpt on cpt.SingleTag = t.TagName
        join Posts p on p.Id = cpt.PostId and p.OwnerUserId = u.Id
        order by t.QuestionCount desc nulls last
        limit 1
    ) tc on true
    left join Lateral (
        select vsm.UpVotes, vsm.DownVotes, vsm.Favorites, vsm.TotalBounty
        from Posts p
        join VotesSummary vsm on vsm.PostId = p.Id
        where p.OwnerUserId = u.Id
        order by p.LastActivityDate desc nulls last
        limit 1
    ) vsm on true
    where u.Reputation > 1000
)
select *
from FinalResult
order by AcceptedAnswers desc nulls last, GoldBadges desc nulls last, AnswersGiven desc nulls last
limit 100;