with RecursiveUserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreation,
        row_number() over (partition by u.Id order by p.CreationDate) as PostSeq,
        count(*) over (partition by u.Id) as TotalPosts,
        case when p.PostTypeId = 1 then p.AcceptedAnswerId else null end as AcceptedAnswerId
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserPostLinks as (
    select
        r.UserId,
        pl.LinkTypeId,
        count(distinct pl.Id) as LinkCount
    from RecursiveUserActivity r
    join PostLinks pl on pl.PostId = r.PostId
    group by r.UserId, pl.LinkTypeId
),
UserCommentStats as (
    select
        c.UserId,
        count(distinct c.Id) as CommentsMade,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > (cast('2024-10-01' as date) - interval '30 days') then 1 else 0 end) as RecentComments
    from Comments c
    group by c.UserId
),
LatestPostHistories as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.UserId as EditorUserId,
        ph.PostHistoryTypeId,
        ph.CreationDate as EditDate,
        ph.Comment as EditComment
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    order by ph.PostId, ph.CreationDate desc
),
UserActivityWindow as (
    select
        r.UserId,
        r.PostId,
        r.PostCreation,
        lag(r.PostCreation) over (partition by r.UserId order by r.PostCreation) as PrevPostDate,
        lead(r.PostCreation) over (partition by r.UserId order by r.PostCreation) as NextPostDate,
        coalesce(
            extract(epoch from (r.PostCreation - lag(r.PostCreation) over (partition by r.UserId order by r.PostCreation))),
            0) as SecondsSincePrevPost,
        coalesce(
            extract(epoch from (lead(r.PostCreation) over (partition by r.UserId order by r.PostCreation) - r.PostCreation)),
            0) as SecondsUntilNextPost,
        row_number() over (partition by r.UserId order by r.PostCreation desc) as PostSeqDesc
    from RecursiveUserActivity r
),
UserAggregate as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as QuestionCount,
        coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(max(p.ViewCount),0) as MaxViewCount,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges,
        coalesce(cs.CommentsMade,0) as TotalComments,
        coalesce(cs.RecentComments,0) as RecentComments
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            UserId,
            max(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
            max(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
            max(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
        from UserBadgeCounts
        group by UserId
    ) bc on bc.UserId = u.Id
    left join UserCommentStats cs on cs.UserId = u.Id
    where u.Reputation >= 500
    group by u.Id, u.DisplayName, u.Reputation, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges, cs.CommentsMade, cs.RecentComments
),
DuplicateQuestions as (
    select distinct p.Id as QuestionId, pl.RelatedPostId as DuplicateOfId
    from Posts p
    join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    where p.PostTypeId = 1
),
HighlyViewedQuestions as (
    select
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        coalesce(us.Reputation,0) as OwnerReputation,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Posts p
    left join Users us on us.Id = p.OwnerUserId
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 1 and p.ViewCount > 10000
    group by p.Id, p.Title, p.ViewCount, p.Score, us.Reputation
),
UserRanking as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        rank() over (order by ua.Reputation desc, ua.TotalPostScore desc) as ReputationRank,
        dense_rank() over (order by ua.GoldBadges desc, ua.SilverBadges desc, ua.BronzeBadges desc) as BadgeRank
    from UserAggregate ua
)
select
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.ReputationRank,
    ur.BadgeRank,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalPostScore,
    ua.MaxViewCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalComments,
    ua.RecentComments,
    coalesce(dl.DuplicateOfId, -1) as DuplicateQuestionId,
    hq.Title as HighlyViewedQuestionTitle,
    hq.ViewCount as HighlyViewedQuestionViews,
    hq.UpVotes,
    hq.DownVotes,
    latest.EditDate as LastEditDate,
    latest.PostHistoryTypeId as LastEditType,
    latest.EditComment as LastEditComment,
    uaw.SecondsSincePrevPost,
    uaw.SecondsUntilNextPost,
    case
        when ua.Reputation > 5000 and ua.TotalPostScore > 1000 then 'Highly Active'
        when ua.Reputation between 1000 and 5000 then 'Moderately Active'
        else 'Less Active'
    end as ActivityLevel,
    concat(
        ur.DisplayName,
        ' | ',
        'Rep: ', ur.Reputation,
        ' | Q: ', ua.QuestionCount,
        ' | A: ', ua.AnswerCount,
        ' | Comments: ', ua.TotalComments,
        ' | Badges G/S/B: ', ua.GoldBadges, '/', ua.SilverBadges, '/', ua.BronzeBadges
    ) as UserSummary
from UserRanking ur
join UserAggregate ua on ua.UserId = ur.UserId
left join DuplicateQuestions dl on dl.QuestionId = (
    select p.Id from Posts p where p.OwnerUserId = ur.UserId and p.PostTypeId = 1 order by p.CreationDate desc limit 1
)
left join HighlyViewedQuestions hq on hq.Id = (
    select p.Id from Posts p where p.OwnerUserId = ur.UserId and p.PostTypeId = 1 order by p.ViewCount desc limit 1
)
left join LatestPostHistories latest on latest.PostId = (
    select p.Id from Posts p where p.OwnerUserId = ur.UserId order by p.LastEditDate desc nulls last limit 1
)
left join UserActivityWindow uaw on uaw.UserId = ur.UserId and uaw.PostId = (
    select r.PostId from RecursiveUserActivity r where r.UserId = ur.UserId order by r.PostSeq desc limit 1
)
where ur.ReputationRank <= 100
order by ur.ReputationRank
limit 50;