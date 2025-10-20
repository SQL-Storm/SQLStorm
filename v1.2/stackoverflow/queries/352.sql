with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        max(b.Date) as LastBadgeDate,
        row_number() over (partition by u.Location order by u.Reputation desc) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopTags as (
    select 
        t.TagName,
        t.Count,
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like ('%' || '<' || t.TagName || '>' || '%')
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 1000
),
UserTagStats as (
    select 
        ua.UserId,
        ua.DisplayName,
        tt.TagName,
        count(tt.QuestionId) as QuestionsAsked,
        avg(tt.Score) as AvgQuestionScore,
        max(tt.ViewCount) as MaxViewCount,
        sum(case when tt.Score >= 10 then 1 else 0 end) as HighScoreQuestions
    from RecursiveUserActivity ua
    join TopTags tt on tt.OwnerUserId = ua.UserId
    group by ua.UserId, ua.DisplayName, tt.TagName
),
PostCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = CAST(ph.Comment AS integer)
    where ph.PostHistoryTypeId = 10
),
PostVotesSummary as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as Favorites,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
),
AnswerRanks as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswersWithAccepted as (
    select 
        ar.AnswerId,
        ar.QuestionId,
        ar.Score,
        ar.CreationDate,
        ar.AnswerRank,
        q.AcceptedAnswerId,
        case when ar.AnswerId = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from AnswerRanks ar
    join Posts q on q.Id = ar.QuestionId and q.PostTypeId = 1
    where ar.AnswerRank <= 5
),
UserActivitySummary as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.BadgeCount,
        ua.LastBadgeDate,
        uts.TagName,
        uts.QuestionsAsked,
        uts.AvgQuestionScore,
        uts.MaxViewCount,
        uts.HighScoreQuestions,
        pcs.CloseReason,
        pcs.CloseDate,
        pvs.UpVotes as PostUpVotes,
        pvs.DownVotes as PostDownVotes,
        pvs.Favorites as PostFavorites,
        pvs.TotalBounty,
        ta.AnswerId,
        ta.Score as AnswerScore,
        ta.AnswerRank,
        ta.IsAccepted
    from RecursiveUserActivity ua
    left join UserTagStats uts on uts.UserId = ua.UserId
    left join PostCloseReasons pcs on pcs.PostId = (select min(p.Id) from Posts p where p.OwnerUserId = ua.UserId and p.PostTypeId = 1)
    left join PostVotesSummary pvs on pvs.PostId = (select min(p.Id) from Posts p where p.OwnerUserId = ua.UserId)
    left join TopAnswersWithAccepted ta on ta.AnswerId = (select min(a.Id) from Posts a where a.OwnerUserId = ua.UserId and a.PostTypeId = 2)
)
select 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    coalesce(uas.Location, 'Unknown') as Location,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.BadgeCount,
    CAST(uas.LastBadgeDate AS date) as LastBadgeDate,
    uas.TagName,
    uas.QuestionsAsked,
    round(CAST(uas.AvgQuestionScore AS numeric), 2) as AvgQuestionScore,
    uas.MaxViewCount,
    uas.HighScoreQuestions,
    uas.CloseReason,
    CAST(uas.CloseDate AS date) as CloseDate,
    uas.PostUpVotes,
    uas.PostDownVotes,
    uas.PostFavorites,
    coalesce(uas.TotalBounty, 0) as TotalBounty,
    uas.AnswerId,
    uas.AnswerScore,
    uas.AnswerRank,
    uas.IsAccepted,
    case 
        when uas.Reputation > 10000 then 'Expert'
        when uas.Reputation between 5000 and 10000 then 'Intermediate'
        else 'Beginner'
    end as UserLevel,
    case 
        when uas.HighScoreQuestions > 5 then 'High Impact'
        else 'Normal Impact'
    end as ImpactLevel,
    (coalesce(uas.TagName, 'NoTag') || ' | ' || 'Q:' || coalesce(CAST(uas.QuestionsAsked AS varchar), '0') || ' | ' || 'A:' || CAST(uas.AnswerCount AS varchar) || ' | ' || 'Badges:' || CAST(uas.BadgeCount AS varchar)) as SummaryString
from UserActivitySummary uas
where uas.QuestionCount > 10
group by
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    coalesce(uas.Location, 'Unknown'),
    uas.Location,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.BadgeCount,
    CAST(uas.LastBadgeDate AS date),
    uas.TagName,
    uas.QuestionsAsked,
    round(CAST(uas.AvgQuestionScore AS numeric), 2),
    uas.MaxViewCount,
    uas.HighScoreQuestions,
    uas.CloseReason,
    CAST(uas.CloseDate AS date),
    uas.PostUpVotes,
    uas.PostDownVotes,
    uas.PostFavorites,
    coalesce(uas.TotalBounty, 0),
    uas.AnswerId,
    uas.AnswerScore,
    uas.AnswerRank,
    uas.IsAccepted
order by uas.Reputation desc, uas.Views desc
limit 100;