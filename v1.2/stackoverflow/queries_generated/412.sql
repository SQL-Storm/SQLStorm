-- {"query": "412.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1572} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as Ancestors
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select 
        t.Id,
        t.TagName,
        t.Count,
        r.Ancestors || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Ancestors)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score as QuestionScore,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > q.Score then 1 else 0 end) as AnswersBetterThanQuestion,
        string_agg(distinct coalesce(u.DisplayName, 'Unknown'), ', ') as AnswererNames
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score
),
AnswerWindowStats as (
    select 
        a.Id,
        a.ParentId,
        a.Score,
        u.DisplayName as AnswerOwner,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswersForQuestion,
        lag(a.Score) over (partition by a.ParentId order by a.Score desc) as PrevAnswerScore,
        lead(a.Score) over (partition by a.ParentId order by a.Score desc) as NextAnswerScore
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
QuestionCloseInfo as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserUserName
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) 
        and ph.PostHistoryTypeId = 10
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
QuestionVoteSummary as (
    select 
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id
),
TopQuestionsWithDetails as (
    select 
        qas.QuestionId,
        qas.Title,
        qas.OwnerUserId,
        u.DisplayName as QuestionOwnerName,
        qas.CreationDate,
        qas.QuestionScore,
        qvs.UpVotes,
        qvs.DownVotes,
        qvs.Favorites,
        qvs.TotalBounty,
        qas.TotalAnswers,
        qas.MaxAnswerScore,
        qas.AvgAnswerScore,
        qas.AnswersBetterThanQuestion,
        qas.AnswererNames,
        qci.CloseReason,
        qci.CloseDate,
        qci.CloserUserName
    from PostAnswerStats qas
    left join Users u on u.Id = qas.OwnerUserId
    left join QuestionVoteSummary qvs on qvs.PostId = qas.QuestionId
    left join QuestionCloseInfo qci on qci.PostId = qas.QuestionId
    where qas.TotalAnswers > 0
),
FinalRankedQuestions as (
    select 
        *,
        rank() over (order by QuestionScore desc, TotalAnswers desc, UpVotes desc) as RankByScoreAnswers
    from TopQuestionsWithDetails
),
UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersProvided,
        count(distinct c.Id) as CommentsMade,
        count(distinct b.Id) as BadgesEarned,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        greatest(max(p.CreationDate), max(c.CreationDate)) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
select 
    frq.RankByScoreAnswers,
    frq.QuestionId,
    frq.Title,
    frq.QuestionOwnerName,
    frq.CreationDate,
    frq.QuestionScore,
    frq.UpVotes,
    frq.DownVotes,
    frq.Favorites,
    frq.TotalBounty,
    frq.TotalAnswers,
    frq.MaxAnswerScore,
    round(frq.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    frq.AnswersBetterThanQuestion,
    frq.AnswererNames,
    coalesce(frq.CloseReason, 'Open') as CloseStatus,
    frq.CloseDate,
    frq.CloserUserName,
    uas.QuestionsAsked,
    uas.AnswersProvided,
    uas.CommentsMade,
    uas.BadgesEarned,
    uas.LastActivityDate,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges
from FinalRankedQuestions frq
left join UserActivitySummary uas on uas.UserId = frq.OwnerUserId
left join UserBadgeStats ub on ub.UserId = frq.OwnerUserId
where frq.RankByScoreAnswers <= 50
order by frq.RankByScoreAnswers, frq.QuestionScore desc;