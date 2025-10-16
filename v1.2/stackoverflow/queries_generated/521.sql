-- {"query": "521.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1423} 
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
        coalesce(sum(v.VoteCount), 0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod or DownMod
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsersWithBadges as (
    select
        ua.*,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.Date as BadgeDate,
        row_number() over (partition by ua.UserId order by b.Class, b.Date desc) as BadgeRank
    from RecursiveUserActivity ua
    left join Badges b on b.UserId = ua.UserId
    where b.TagBased = 0 or b.TagBased is null
),
UserBadgeSummary as (
    select
        UserId,
        count(*) filter (where BadgeClass = 1) as GoldBadges,
        count(*) filter (where BadgeClass = 2) as SilverBadges,
        count(*) filter (where BadgeClass = 3) as BronzeBadges,
        string_agg(distinct BadgeName, ', ') as BadgeNames
    from TopUsersWithBadges
    group by UserId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwner,
        a.CreationDate as AnswerCreation,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswersPerQuestion as (
    select
        QuestionId,
        AnswerId,
        AnswerScore,
        AnswerOwner,
        AnswerCreation
    from QuestionAnswerStats
    where AnswerRank = 1
),
QuestionsWithCloseInfo as (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from Posts q
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where q.PostTypeId = 1
),
UserActivityWithWindow as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.TotalVotesReceived,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ua.UserRank,
        lead(ua.Reputation) over (order by ua.Reputation desc) as NextHigherReputation,
        lag(ua.Reputation) over (order by ua.Reputation desc) as NextLowerReputation
    from RecursiveUserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
),
QuestionsWithDuplicateLinks as (
    select
        q.Id as QuestionId,
        q.Title,
        count(pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where q.PostTypeId = 1
    group by q.Id, q.Title
),
ComplexStringAnalysis as (
    select
        p.Id as PostId,
        p.Title,
        p.Tags,
        array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), 1) as TagCount,
        length(p.Body) as BodyLength,
        position('sql' in lower(p.Body)) as PosSql,
        case when p.Body is null then 'No Body'
             when length(p.Body) > 1000 then 'Long Body'
             else 'Short Body'
        end as BodyCategory
    from Posts p
    where p.PostTypeId = 1
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalVotesReceived,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.UserRank,
    ua.NextHigherReputation,
    ua.NextLowerReputation,
    qwi.CloseReasonName,
    qwi.CloseDate,
    dup.DuplicateCount,
    ca.TagCount,
    ca.BodyLength,
    ca.PosSql,
    ca.BodyCategory,
    ta.AnswerId as TopAnswerId,
    ta.AnswerScore as TopAnswerScore,
    ta.AnswerOwner as TopAnswerOwner,
    ta.AnswerCreation as TopAnswerCreation
from UserActivityWithWindow ua
left join QuestionsWithCloseInfo qwi on qwi.Id = ua.UserId -- intentional mismatch to force NULLs for outer join complexity
left join QuestionsWithDuplicateLinks dup on dup.QuestionId = ua.UserId -- intentional mismatch
left join ComplexStringAnalysis ca on ca.PostId = ua.UserId -- intentional mismatch
left join TopAnswersPerQuestion ta on ta.QuestionId = ua.UserId -- intentional mismatch
where ua.Reputation > (
    select avg(Reputation) from Users where Reputation is not null
)
and (
    ua.GoldBadges > 0 or ua.SilverBadges > 2 or ua.BronzeBadges > 5
)
order by ua.Reputation desc, ua.UserRank
limit 100;