-- {"query": "740.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1268} 
with RecursiveUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) filter (where b.Class is not null) as HighestBadgeClass,
        coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as QuestionCount,
        coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        row_number() over (order by u.Reputation desc, u.Id) as RankByReputation
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopUsersQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CreationDate,
        ru.RankByReputation,
        ru.BadgeCount,
        ru.HighestBadgeClass,
        ru.Reputation as UserReputation,
        string_agg(distinct lt.Name, ', ') filter (where lt.Name is not null) as LinkTypesToDuplicates,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevQuestionScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextQuestionScore
    from Posts p
    inner join RecursiveUserStats ru on ru.UserId = p.OwnerUserId
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3 -- duplicate links
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.PostTypeId = 1
),
FilteredQuestions as (
    select
        tq.*,
        -- Extract first tag from Tags string like '<tag1><tag2><tag3>'
        substring(tq.Tags from '<([^>]+)>') as FirstTag,
        -- Count of tags by splitting Tags string
        array_length(string_to_array(regexp_replace(tq.Tags, '[<>]', '', 'g'), '><'), 1) as TagCount,
        -- Calculate score difference with previous and next questions
        coalesce(tq.Score - coalesce(tq.PrevQuestionScore, 0), 0) as ScoreDiffPrev,
        coalesce(tq.NextQuestionScore - tq.Score, 0) as ScoreDiffNext,
        -- Complex predicate: questions that have more than 2 answers or more than 5 favorites or are linked as duplicates
        case
            when tq.AnswerCount > 2 or tq.FavoriteCount > 5 or tq.LinkTypesToDuplicates is not null then true
            else false
        end as IsPopularOrDuplicate
    from TopUsersQuestions tq
    where rq.RankByReputation <= 100
),
QuestionRanks as (
    select
        fq.*,
        rank() over (partition by fq.FirstTag order by fq.Score desc, fq.ViewCount desc) as TagScoreRank,
        dense_rank() over (order by fq.UserReputation desc) as UserReputationRank
    from FilteredQuestions fq
    join RecursiveUserStats rq on rq.UserId = fq.OwnerUserId
),
AggregatedResults as (
    select
        qr.FirstTag,
        count(*) as TotalQuestions,
        avg(qr.Score) as AvgScore,
        sum(qr.ViewCount) as TotalViews,
        avg(qr.TagCount) as AvgTagCount,
        count(distinct qr.OwnerUserId) as DistinctUsers,
        max(qr.Score) as MaxScore,
        min(qr.Score) as MinScore,
        sum(case when qr.IsPopularOrDuplicate then 1 else 0 end) as PopularOrDuplicateCount,
        string_agg(distinct qr.LinkTypesToDuplicates, ', ') as AllDuplicateLinkTypes
    from QuestionRanks qr
    group by qr.FirstTag
)
select
    ar.FirstTag,
    ar.TotalQuestions,
    ar.AvgScore,
    ar.TotalViews,
    ar.AvgTagCount,
    ar.DistinctUsers,
    ar.MaxScore,
    ar.MinScore,
    ar.PopularOrDuplicateCount,
    coalesce(ar.AllDuplicateLinkTypes, 'None') as AllDuplicateLinkTypes,
    ru.DisplayName as TopUserDisplayName,
    ru.Reputation as TopUserReputation,
    ru.BadgeCount as TopUserBadgeCount,
    ru.HighestBadgeClass as TopUserHighestBadgeClass,
    ru.Views as TopUserViews,
    ru.UpVotes as TopUserUpVotes,
    ru.DownVotes as TopUserDownVotes,
    ru.CreationDate as TopUserCreationDate
from AggregatedResults ar
left join RecursiveUserStats ru on ru.UserId = (
    select OwnerUserId from Posts p2
    where p2.PostTypeId = 1
    and substring(p2.Tags from '<([^>]+)>') = ar.FirstTag
    order by p2.Score desc, p2.ViewCount desc
    limit 1
)
where ar.TotalQuestions > 10
order by ar.TotalQuestions desc, ar.AvgScore desc;