with recursive UsersWithPopularBadges as (
    select
        Badge.UserId,
        U.DisplayName,
        count(*) as GoldBadgeCount
    from Badges Badge
    join Users U on Badge.UserId = U.Id
    where Badge.Class = 1
    group by Badge.UserId, U.DisplayName
    having count(*) > 3
), QuestionStats as (
    -- Basic post + stats with text length + special tags analysis
    select
        p.Id as PostId,
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        length(coalesce(p.Body, '')) as BodyLength,
        length(coalesce(p.Title, '')) as TitleLength,
        -- array-like tag parsing: remove angle brackets and split by '><' is dialect-specific;
        -- here we count occurrences of distinct tags by simple pattern matching examples:
        case when p.Tags like '%<sql>%' then 1 else 0 end as HasTag_sql,
        case when p.Tags like '%<javascript>%' then 1 else 0 end as HasTag_javascript,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.Score, 0) as Score
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 -- questions only
), QuestionAggregates as (
    select
        qs.PostId,
        qs.OwnerUserId,
        qs.DisplayName,
        qs.CreationDate,
        qs.BodyLength,
        qs.TitleLength,
        sum(qs.HasTag_sql) as HasTag_sql,
        sum(qs.HasTag_javascript) as HasTag_javascript,
        sum(qs.ViewCount) as ViewCount,
        sum(qs.AnswerCount) as AnswerCount,
        sum(qs.Score) as Score
    from QuestionStats qs
    group by
        qs.PostId,
        qs.OwnerUserId,
        qs.DisplayName,
        qs.CreationDate,
        qs.BodyLength,
        qs.TitleLength
)
select
    qa.PostId,
    qa.OwnerUserId,
    qa.DisplayName,
    qa.CreationDate,
    qa.BodyLength,
    qa.TitleLength,
    qa.HasTag_sql,
    qa.HasTag_javascript,
    qa.ViewCount,
    qa.AnswerCount,
    qa.Score,
    uwb.GoldBadgeCount
from QuestionAggregates qa
left join UsersWithPopularBadges uwb on qa.OwnerUserId = uwb.UserId
order by qa.CreationDate desc
limit 100;