-- {"query": "517.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1382} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t.TagName
    from Tags t
    inner join RecursiveTagHierarchy r on t.Id = r.Id + 1
    where r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyGiven,
        max(p.CreationDate) as LastPostDate,
        row_number() over (partition by u.Id order by p.Score desc nulls last) as TopPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes vb on vb.UserId = u.Id and vb.VoteTypeId in (8,9) -- BountyStart and BountyClose
    group by u.Id, u.DisplayName, u.Reputation
),
AcceptedAnswersWithScores as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        row_number() over (partition by q.Id order by a.Score desc nulls last) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.Comment, crt.Name
),
UserBadgeSummary as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        string_agg(distinct b.Name, ', ') as BadgeNames
    from Badges b
    group by b.UserId, b.Class
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId end) as LinkedPostsCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicatePostsCount
    from PostLinks pl
    group by pl.PostId
),
FinalUserStats as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.TotalBountyGiven,
        ua.LastPostDate,
        coalesce(ubs_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubs_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubs_bronze.BadgeCount,0) as BronzeBadges,
        (ua.QuestionCount + ua.AnswerCount + ua.CommentCount) as TotalContributions,
        case
            when ua.Reputation >= 10000 then 'Expert'
            when ua.Reputation >= 1000 then 'Intermediate'
            else 'Beginner'
        end as UserLevel
    from UserActivity ua
    left join UserBadgeSummary ubs_gold on ubs_gold.UserId = ua.UserId and ubs_gold.Class = 1
    left join UserBadgeSummary ubs_silver on ubs_silver.UserId = ua.UserId and ubs_silver.Class = 2
    left join UserBadgeSummary ubs_bronze on ubs_bronze.UserId = ua.UserId and ubs_bronze.Class = 3
)
select
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.UserLevel,
    fus.QuestionCount,
    fus.AnswerCount,
    fus.CommentCount,
    fus.TotalContributions,
    fus.TotalBountyGiven,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    array_agg(distinct rth.Path order by rth.Level) filter (where rth.Path is not null) as SampleTagPaths,
    cac.CloseReasonName,
    cac.CloseCount,
    aas.AnswerId,
    aas.AnswerScore,
    pls.LinkedPostsCount,
    pls.DuplicatePostsCount,
    case
        when aas.AnswerScore is null then 'No Answers'
        when aas.AnswerScore > 10 then 'Highly Rated Answer'
        else 'Answered'
    end as AnswerQuality,
    length(coalesce(p.Body, '')) as QuestionBodyLength,
    strpos(lower(coalesce(p.Title, '')), 'sql') > 0 as TitleContainsSQL,
    case when p.ClosedDate is not null then 'Closed' else 'Open' end as QuestionStatus
from FinalUserStats fus
left join AcceptedAnswersWithScores aas on aas.AnswerOwner = fus.UserId and aas.AnswerRank = 1
left join Posts p on p.Id = aas.QuestionId
left join RecursiveTagHierarchy rth on rth.Id = any(string_to_array(trim(both '<>' from coalesce(p.Tags, '')), '><')::int[])
left join CloseReasonCounts cac on cac.CloseReasonId = (
    select ph.Comment
    from PostHistory ph
    where ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc
    limit 1
)
left join PostLinkSummary pls on pls.PostId = p.Id
where fus.TotalContributions > 10
order by fus.Reputation desc, fus.TotalContributions desc
limit 100;