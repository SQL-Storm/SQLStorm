-- {"query": "91.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1605} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsers as (
    select * from RecursiveUserActivity where UserRank <= 100
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        p.LastActivityDate,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        case 
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        -- Extract first tag from Tags string, which is in format '<tag1><tag2><tag3>'
        substring(p.Tags from '<([^>]+)>') as FirstTag
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2)
),
PostLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as TotalAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(case when p.Score > 0 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PositiveScorePostsLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserTopTags as (
    select
        p.OwnerUserId as UserId,
        tag,
        count(*) as TagCount,
        row_number() over (partition by p.OwnerUserId order by count(*) desc) as TagRank
    from Posts p
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as tag
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, tag
),
UserTopTagSummary as (
    select
        UserId,
        string_agg(tag, ', ') as TopTags
    from UserTopTags
    where TagRank <= 3
    group by UserId
),
CombinedUserStats as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionCount,
        u.AnswerCount,
        u.CommentCount,
        u.BadgeCount,
        coalesce(ubs.GoldBadges, 0) as GoldBadges,
        coalesce(ubs.SilverBadges, 0) as SilverBadges,
        coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
        coalesce(uts.TopTags, '') as TopTags
    from TopUsers u
    left join UserBadgeSummary ubs on ubs.UserId = u.UserId
    left join UserTopTagSummary uts on uts.UserId = u.UserId
)
select
    cus.UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.QuestionCount,
    cus.AnswerCount,
    cus.CommentCount,
    cus.BadgeCount,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.TopTags,
    pd.Id as RecentQuestionId,
    pd.Title as RecentQuestionTitle,
    pd.Score as RecentQuestionScore,
    pd.ViewCount as RecentQuestionViews,
    pd.AnswerCount as RecentQuestionAnswerCount,
    pd.IsClosed as RecentQuestionIsClosed,
    acr.CloseReasonName as RecentQuestionCloseReason,
    ans.TotalAnswers,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.MinAnswerScore,
    case 
        when pd.AcceptedAnswerId is not null then 1
        else 0
    end as HasAcceptedAnswer,
    -- Correlated subquery to get the highest scoring answer's owner display name
    (select u2.DisplayName from Posts p2
     join Users u2 on u2.Id = p2.OwnerUserId
     where p2.ParentId = pd.Id
     order by p2.Score desc nulls last limit 1) as TopAnswerOwner,
    -- String expression combining user display name and top tags
    concat(cus.DisplayName, ' [Top Tags: ', coalesce(cus.TopTags, 'None'), ']') as UserTagSummary
from CombinedUserStats cus
left join lateral (
    select p.*
    from Posts p
    where p.OwnerUserId = cus.UserId and p.PostTypeId = 1
    order by p.CreationDate desc
    limit 1
) pd on true
left join AnswerStats ans on ans.QuestionId = pd.Id
left join QuestionCloseReasons acr on acr.PostId = pd.Id
order by cus.Reputation desc, cus.UserId
limit 50;