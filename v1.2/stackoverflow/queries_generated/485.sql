-- {"query": "485.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1662} 
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
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUserBadges as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by b.UserId) as BadgeCount,
        dense_rank() over (partition by b.UserId order by b.Class asc, b.Date desc) as BadgeRank
    from Badges b
    where b.Class in (1,2,3)
),
UserTopBadges as (
    select distinct on (UserId)
        UserId,
        BadgeName,
        Class,
        BadgeCount
    from TopUserBadges
    where BadgeRank = 1
    order by UserId, BadgeRank
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(a.AcceptedAnswerScore,0) as AcceptedAnswerScore,
        coalesce(a.AcceptedAnswerUserReputation,0) as AcceptedAnswerUserReputation,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join (
        select
            q.Id as QuestionId,
            a.Score as AcceptedAnswerScore,
            u.Reputation as AcceptedAnswerUserReputation
        from Posts q
        left join Posts a on a.Id = q.AcceptedAnswerId
        left join Users u on u.Id = a.OwnerUserId
        where q.PostTypeId = 1 and a.PostTypeId = 2
    ) a on a.QuestionId = p.Id
    where p.PostTypeId = 1
),
TagExplode as (
    select
        QuestionId,
        unnest(string_to_array(substring(Tags from 2 for length(Tags)-2), '><')) as Tag
    from QuestionStats
    where Tags is not null
),
TagPopularity as (
    select
        Tag,
        count(distinct QuestionId) as QuestionCount,
        avg(Score) as AvgScore,
        sum(ViewCount) as TotalViews
    from TagExplode te
    join QuestionStats qs on qs.QuestionId = te.QuestionId
    group by Tag
),
UserTagEngagement as (
    select
        ru.UserId,
        ru.DisplayName,
        te.Tag,
        count(distinct te.QuestionId) as UserQuestionsWithTag,
        sum(qs.ViewCount) as UserTagViews,
        sum(qs.Score) as UserTagScore,
        rank() over (partition by ru.UserId order by count(distinct te.QuestionId) desc) as TagRank
    from RecursiveUserActivity ru
    join Posts p on p.OwnerUserId = ru.UserId and p.PostTypeId = 1
    join QuestionStats qs on qs.QuestionId = p.Id
    join TagExplode te on te.QuestionId = qs.QuestionId
    group by ru.UserId, ru.DisplayName, te.Tag
),
TopUserTags as (
    select
        UserId,
        DisplayName,
        Tag,
        UserQuestionsWithTag,
        UserTagViews,
        UserTagScore
    from UserTagEngagement
    where TagRank <= 3
),
UserCloseReasons as (
    select
        ph.UserId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.UserId is not null
    group by ph.UserId, crt.Name
),
UserSummary as (
    select
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.CommentCount,
        ru.TotalVotesReceived,
        utb.BadgeName as TopBadge,
        utb.Class as TopBadgeClass,
        utb.BadgeCount as TopBadgeCount,
        array_agg(distinct tut.Tag order by tut.UserQuestionsWithTag desc) filter (where tut.Tag is not null) as TopTags,
        coalesce(sum(ucr.CloseCount),0) as TotalCloseVotes,
        max(ucr.CloseCount) filter (where ucr.CloseReason is not null) as MaxCloseVotesForOneReason
    from RecursiveUserActivity ru
    left join UserTopBadges utb on utb.UserId = ru.UserId
    left join TopUserTags tut on tut.UserId = ru.UserId
    left join UserCloseReasons ucr on ucr.UserId = ru.UserId
    group by ru.UserId, ru.DisplayName, ru.Reputation, ru.QuestionCount, ru.AnswerCount, ru.CommentCount, ru.TotalVotesReceived, utb.BadgeName, utb.Class, utb.BadgeCount
)
select
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.CommentCount,
    us.TotalVotesReceived,
    us.TopBadge,
    case us.TopBadgeClass
        when 1 then 'Gold'
        when 2 then 'Silver'
        when 3 then 'Bronze'
        else 'None'
    end as TopBadgeClass,
    us.TopBadgeCount,
    coalesce(array_to_string(us.TopTags, ', '), 'No Top Tags') as TopTags,
    us.TotalCloseVotes,
    us.MaxCloseVotesForOneReason,
    qs.Title as MostRecentQuestionTitle,
    qs.Score as MostRecentQuestionScore,
    qs.ViewCount as MostRecentQuestionViews,
    qs.AnswerCount as MostRecentQuestionAnswers,
    qs.IsClosed as MostRecentQuestionClosed,
    case when qs.AcceptedAnswerScore > 0 then 'Has Accepted Answer' else 'No Accepted Answer' end as AcceptedAnswerStatus,
    concat(
        'Q:', qs.Title, ' | Score:', qs.Score, ' | Views:', qs.ViewCount, ' | Answers:', qs.AnswerCount,
        ' | AcceptedAnswerScore:', coalesce(qs.AcceptedAnswerScore::text, '0'),
        ' | Closed:', case when qs.IsClosed = 1 then 'Yes' else 'No' end
    ) as QuestionSummary
from UserSummary us
left join QuestionStats qs on qs.OwnerUserId = us.UserId and qs.RecentQuestionRank = 1
where us.Reputation > 10000
order by us.Reputation desc, us.TotalVotesReceived desc
limit 50;