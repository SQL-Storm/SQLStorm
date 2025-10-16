-- {"query": "367.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1654} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews
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
        coalesce(sum(v.BountyAmount), 0) as TotalBountyEarned
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id and v.VoteTypeId = 8 -- BountyStart votes given by user
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
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    where p.OwnerUserId is not null
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as ClosedDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
),
UserCommentStats as (
    select
        c.UserId,
        u.DisplayName,
        count(c.Id) as TotalComments,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > current_date - interval '30 days' then 1 else 0 end) as CommentsLast30Days
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
TopAnswerers as (
    select
        p.OwnerUserId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.OwnerUserId
),
UserReputationGrowth as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        lead(u.Reputation) over (order by u.CreationDate) - u.Reputation as NextUserRepDiff
    from Users u
),
QuestionsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        (select count(*) from Comments c where c.PostId = q.Id) as QuestionCommentCount,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    coalesce(ubs.TotalBountyEarned, 0) as TotalBountyEarned,
    coalesce(tc.Count, 0) as TagCount,
    coalesce(tc.TotalAnswers, 0) as TagTotalAnswers,
    coalesce(tc.TotalViews, 0) as TagTotalViews,
    coalesce(tas.AnswerCount, 0) as TotalAnswers,
    coalesce(tas.AvgAnswerScore, 0) as AvgAnswerScore,
    coalesce(tas.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(ucs.TotalComments, 0) as TotalComments,
    coalesce(ucs.AvgCommentLength, 0) as AvgCommentLength,
    coalesce(ucs.CommentsLast30Days, 0) as CommentsLast30Days,
    coalesce(cqwr.ClosedCount, 0) as ClosedQuestionsCount,
    coalesce(dls.DuplicateCount, 0) as DuplicateLinksCount,
    case when u.Location is null or length(trim(u.Location)) = 0 then 'Unknown' else u.Location end as UserLocation,
    case when u.WebsiteUrl is not null and u.WebsiteUrl like 'https://%' then 'SecureWebsite' else 'NonSecureOrNoWebsite' end as WebsiteSecurity,
    case when u.AboutMe is null then 'NoAboutMe' else 'HasAboutMe' end as AboutMeStatus,
    row_number() over (order by u.Reputation desc) as UserRankByReputation
from Users u
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join RecursiveTagCounts tc on tc.TagName = (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'))
    from Posts p
    where p.OwnerUserId = u.Id and p.PostTypeId = 1
    order by p.CreationDate desc limit 1
)
left join TopAnswerers tas on tas.OwnerUserId = u.Id
left join UserCommentStats ucs on ucs.UserId = u.Id
left join (
    select
        ph.UserId,
        count(distinct ph.PostId) as ClosedCount
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.UserId
) cqwr on cqwr.UserId = u.Id
left join (
    select
        p.OwnerUserId,
        count(pl.Id) as DuplicateCount
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    inner join Posts p on p.Id = pl.PostId
    group by p.OwnerUserId
) dls on dls.OwnerUserId = u.Id
where u.Reputation > 1000
order by UserRankByReputation
limit 100;