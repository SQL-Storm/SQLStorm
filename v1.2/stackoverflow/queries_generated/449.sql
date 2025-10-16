-- {"query": "449.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1609} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyGiven,
        row_number() over (partition by u.Id order by ph.CreationDate desc nulls last) as LastActivityRank,
        max(ph.CreationDate) as LastPostHistoryDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes vb on vb.UserId = u.Id and vb.VoteTypeId = 8 -- BountyStart
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
    where b.TagBased = 0
),
TopUsers as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalBountyGiven,
        ua.LastPostHistoryDate,
        count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinksMade,
        count(distinct pl.Id) filter (where lt.Name = 'Linked') as LinkedPostsMade,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenActions
    from RecursiveUserActivity ua
    left join PostLinks pl on pl.PostId = ua.UserId
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join PostHistory ph on ph.UserId = ua.UserId
    where ua.Reputation > 10000
    group by ua.UserId, ua.DisplayName, ua.Reputation, ua.CreationDate, ua.LastAccessDate, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.TotalBountyGiven, ua.LastPostHistoryDate
),
UserTopBadges as (
    select
        ub.UserId,
        string_agg(ub.BadgeName || ' (' || 
            case ub.Class
                when 1 then 'Gold'
                when 2 then 'Silver'
                when 3 then 'Bronze'
                else 'Unknown'
            end || ')', ', ' order by ub.BadgeRank) as BadgesList
    from UserBadgeRanks ub
    where ub.BadgeRank <= 5
    group by ub.UserId
),
QuestionStats as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'),1) as TagCount,
        p.CreationDate,
        p.ClosedDate,
        case when p.ClosedDate is not null then true else false end as IsClosed,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    where p.PostTypeId = 1
),
AnswerStats as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        case when a.Id = q.AcceptedAnswerId then true else false end as IsAcceptedAnswer,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRankByScore
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
),
TopQuestionsWithAnswers as (
    select
        qs.Id as QuestionId,
        qs.Title,
        qs.OwnerUserId,
        qs.Score as QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        qs.FavoriteCount,
        qs.TagCount,
        qs.CreationDate as QuestionCreationDate,
        qs.IsClosed,
        ans.Id as AnswerId,
        ans.OwnerUserId as AnswerOwnerUserId,
        ans.Score as AnswerScore,
        ans.IsAcceptedAnswer,
        ans.CreationDate as AnswerCreationDate,
        ans.AnswerRankByScore
    from QuestionStats qs
    left join AnswerStats ans on ans.ParentId = qs.Id
    where qs.UserTopQuestionRank <= 3
),
UserActivitySummary as (
    select
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.QuestionsAsked,
        tu.AnswersGiven,
        tu.CommentsMade,
        tu.TotalBountyGiven,
        tu.DuplicateLinksMade,
        tu.LinkedPostsMade,
        tu.CloseReopenActions,
        coalesce(utb.BadgesList,'') as BadgesList,
        count(distinct tq.QuestionId) as TopQuestionsCount,
        coalesce(avg(tq.QuestionScore),0) as AvgTopQuestionScore,
        coalesce(avg(tq.AnswerScore),0) as AvgTopAnswerScore,
        coalesce(sum(case when tq.IsAcceptedAnswer then 1 else 0 end),0) as AcceptedAnswersCount
    from TopUsers tu
    left join TopQuestionsWithAnswers tq on tq.OwnerUserId = tu.UserId
    left join UserTopBadges utb on utb.UserId = tu.UserId
    group by tu.UserId, tu.DisplayName, tu.Reputation, tu.QuestionsAsked, tu.AnswersGiven, tu.CommentsMade, tu.TotalBountyGiven, tu.DuplicateLinksMade, tu.LinkedPostsMade, tu.CloseReopenActions, utb.BadgesList
)
select
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.CommentsMade,
    uas.TotalBountyGiven,
    uas.DuplicateLinksMade,
    uas.LinkedPostsMade,
    uas.CloseReopenActions,
    uas.BadgesList,
    uas.TopQuestionsCount,
    uas.AvgTopQuestionScore,
    uas.AvgTopAnswerScore,
    uas.AcceptedAnswersCount,
    case
        when uas.Reputation > 50000 and uas.AcceptedAnswersCount > 10 then 'Expert Contributor'
        when uas.Reputation between 10000 and 50000 then 'Active Contributor'
        else 'Casual User'
    end as UserCategory,
    concat_ws(' | ',
        'Q:', uas.QuestionsAsked,
        'A:', uas.AnswersGiven,
        'C:', uas.CommentsMade,
        'Bounty:', uas.TotalBountyGiven
    ) as ActivitySummary
from UserActivitySummary uas
where uas.TopQuestionsCount > 0
order by uas.Reputation desc, uas.AcceptedAnswersCount desc
limit 50;