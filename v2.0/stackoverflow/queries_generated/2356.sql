-- {"query": "2356.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1448} 
with recursive UserExperience as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(u.Location, 'Unknown') as Location,
        coalesce(u.AboutMe, '') as AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as Rank
    from Users u
    where u.Reputation > 1000
),
TopBadges as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by b.UserId, b.Class) as BadgeClassCount
    from Badges b
    where b.Date > (current_date - interval '2 years')
),
QuestionsWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.ViewCount,
        q.Score as QuestionScore,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        avg(a.Score::numeric) as AvgAnswerScore,
        count(distinct c.Id) as CommentCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Comments c on c.PostId = q.Id
    where q.PostTypeId = 1
      and q.CreationDate > (current_date - interval '1 year')
    group by q.Id, q.Title, q.Tags, q.ViewCount, q.Score
),
PostsWithDuplicates as (
    select 
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
PostHistoryCloseDetails as (
    select 
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
RecentActivePosts as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserRecentPostRank
    from Posts p
    where p.PostTypeId in (1, 2)
        and p.CreationDate > (current_date - interval '6 months')
),
UserLastPosts as (
    select 
        u.Id as UserId,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
ComplexUserStats as (
    select 
        ue.Id,
        ue.DisplayName,
        ue.Reputation,
        ue.Location,
        ue.AboutMe,
        coalesce(tb.BadgeClassCount, 0) as RecentBadgeCount,
        coalesce(qa.AnswerCount, 0) as TotalAnswersToRecentQuestions,
        coalesce(pl.DuplicateCount, 0) as TotalDuplicatesLinked,
        coalesce(phcd.CloseDate, null) as LastClosedQuestionDate,
        ulp.LastPostDate,
        ue.Rank,
        case 
            when ulp.LastPostDate is null then 0
            else greatest(0, extract(day from current_date - ulp.LastPostDate))
        end as DaysSinceLastPost
    from UserExperience ue
    left join TopBadges tb on tb.UserId = ue.Id and tb.Class = 1
    left join (
        select 
            a.OwnerUserId,
            count(a.Id) as AnswerCount
        from Posts a
        join Posts q on q.Id = a.ParentId and q.PostTypeId = 1 and q.CreationDate > (current_date - interval '1 year')
        where a.PostTypeId = 2
        group by a.OwnerUserId
    ) qa on qa.OwnerUserId = ue.Id
    left join PostsWithDuplicates pl on pl.PostId in (
        select p.Id from Posts p where p.OwnerUserId = ue.Id
    )
    left join (
        select ph.PostId, ph.CreationDate as CloseDate
        from PostHistory ph
        where ph.PostHistoryTypeId = 10
    ) phcd on phcd.PostId in (
        select p.Id from Posts p where p.OwnerUserId = ue.Id and p.PostTypeId = 1
    )
    left join UserLastPosts ulp on ulp.UserId = ue.Id
)
select 
    cus.DisplayName,
    cus.Reputation,
    cus.Location,
    substring(cus.AboutMe, 1, 100) || case when length(cus.AboutMe) > 100 then '...' else '' end as AboutSnippet,
    cus.RecentBadgeCount,
    cus.TotalAnswersToRecentQuestions,
    cus.TotalDuplicatesLinked,
    to_char(cus.LastClosedQuestionDate, 'YYYY-MM-DD HH24:MI') as LastClosedQuestionDate,
    to_char(cus.LastPostDate, 'YYYY-MM-DD HH24:MI') as LastPostDate,
    cus.DaysSinceLastPost,
    cus.Rank,
    rank() over (order by cus.Reputation desc, cus.DaysSinceLastPost asc) as ReputationRank,
    case 
        when cus.DaysSinceLastPost > 180 then 'Inactive'
        when cus.DaysSinceLastPost between 31 and 180 then 'Moderately Active'
        else 'Highly Active'
    end as ActivityLevel
from ComplexUserStats cus
where cus.Reputation > 1500
order by cus.Reputation desc, cus.DaysSinceLastPost asc
limit 50

union

select 
    'Anonymous' as DisplayName,
    0 as Reputation,
    'Unknown' as Location,
    'No profile information' as AboutSnippet,
    0 as RecentBadgeCount,
    0 as TotalAnswersToRecentQuestions,
    0 as TotalDuplicatesLinked,
    null as LastClosedQuestionDate,
    null as LastPostDate,
    9999 as DaysSinceLastPost,
    9999 as Rank,
    9999 as ReputationRank,
    'Inactive' as ActivityLevel
order by ReputationRank, DaysSinceLastPost
limit 5;