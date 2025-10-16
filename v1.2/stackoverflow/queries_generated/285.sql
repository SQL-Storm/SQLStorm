-- {"query": "285.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2091} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.IsRequired = 1 and t.Id <> r.Id and not t.TagName = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as UpVotesCumulative,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as DownVotesCumulative,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as ReputationRank
    from Users u
    left join Votes v on v.UserId = u.Id and v.CreationDate <= u.CreationDate
),
TopQuestionsWithAnswers as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswerCount
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, p.AcceptedAnswerId
),
QuestionCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        count(distinct b.Id) as BadgesEarned
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionsWithDuplicateLinks as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        pl.RelatedPostId as DuplicateOfQuestionId,
        dup.Title as DuplicateOfTitle
    from Posts q
    left join PostLinks pl on pl.PostId = q.Id and pl.LinkTypeId = 3
    left join Posts dup on dup.Id = pl.RelatedPostId
    where q.PostTypeId = 1
),
AnswerWithUserAndVotes as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        v.VoteTypeId,
        v.CreationDate as VoteDate
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
),
AnswerRankings as (
    select 
        AnswerId,
        QuestionId,
        AnswerScore,
        UserId,
        DisplayName,
        Reputation,
        row_number() over (partition by QuestionId order by AnswerScore desc, AnswerCreationDate asc) as AnswerRank
    from AnswerWithUserAndVotes
),
TopAnswersPerQuestion as (
    select 
        ar.QuestionId,
        ar.AnswerId,
        ar.AnswerScore,
        ar.UserId,
        ar.DisplayName,
        ar.Reputation
    from AnswerRankings ar
    where ar.AnswerRank <= 3
),
ComplexQuestionAnalysis as (
    select 
        tq.QuestionId,
        tq.Title,
        tq.CreationDate,
        tq.Score,
        tq.ViewCount,
        tq.Tags,
        coalesce(qcr.CloseReasonName, 'Open') as CloseStatus,
        tq.AnswerCount,
        tq.MaxAnswerScore,
        tq.AvgAnswerScore,
        tq.PositiveAnswerCount,
        dup.DuplicateOfQuestionId,
        dup.DuplicateOfTitle,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.BadgesEarned,
        ubc.Class as BadgeClass,
        ubc.BadgeCount,
        string_agg(distinct rth.TagName, ',' order by rth.TagName) as RequiredTagsPath,
        ta.AnswerId as TopAnswerId,
        ta.AnswerScore as TopAnswerScore,
        ta.DisplayName as TopAnswerUser,
        ta.Reputation as TopAnswerUserReputation
    from TopQuestionsWithAnswers tq
    left join QuestionCloseReasons qcr on qcr.PostId = tq.QuestionId
    left join QuestionsWithDuplicateLinks dup on dup.QuestionId = tq.QuestionId
    left join UserActivitySummary ua on ua.UserId = tq.OwnerUserId
    left join UserBadgeCounts ubc on ubc.UserId = tq.OwnerUserId and ubc.Class = 1
    left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(tq.Tags, '')) > 0
    left join TopAnswersPerQuestion ta on ta.QuestionId = tq.QuestionId and ta.AnswerRank = 1
    group by 
        tq.QuestionId, tq.Title, tq.CreationDate, tq.Score, tq.ViewCount, tq.Tags, qcr.CloseReasonName, tq.AnswerCount, tq.MaxAnswerScore, tq.AvgAnswerScore, tq.PositiveAnswerCount,
        dup.DuplicateOfQuestionId, dup.DuplicateOfTitle,
        ua.QuestionsPosted, ua.AnswersPosted, ua.CommentsMade, ua.UpVotesGiven, ua.DownVotesGiven, ua.BadgesEarned,
        ubc.Class, ubc.BadgeCount,
        ta.AnswerId, ta.AnswerScore, ta.DisplayName, ta.Reputation
)
select 
    cqa.QuestionId,
    cqa.Title,
    cqa.CreationDate,
    cqa.Score,
    cqa.ViewCount,
    cqa.Tags,
    cqa.CloseStatus,
    cqa.AnswerCount,
    cqa.MaxAnswerScore,
    round(cqa.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    cqa.PositiveAnswerCount,
    cqa.DuplicateOfQuestionId,
    cqa.DuplicateOfTitle,
    cqa.QuestionsPosted,
    cqa.AnswersPosted,
    cqa.CommentsMade,
    cqa.UpVotesGiven,
    cqa.DownVotesGiven,
    cqa.BadgesEarned,
    cqa.BadgeClass,
    cqa.BadgeCount,
    cqa.RequiredTagsPath,
    cqa.TopAnswerId,
    cqa.TopAnswerScore,
    cqa.TopAnswerUser,
    cqa.TopAnswerUserReputation,
    case 
        when cqa.Score > 10 and cqa.ViewCount > 1000 then 'High Impact'
        when cqa.Score between 5 and 10 then 'Moderate Impact'
        else 'Low Impact'
    end as ImpactCategory,
    case 
        when cqa.CloseStatus != 'Open' then 'Closed'
        when cqa.DuplicateOfQuestionId is not null then 'Duplicate'
        else 'Active'
    end as QuestionState,
    length(coalesce(cqa.Title, '')) as TitleLength,
    length(coalesce(cqa.Tags, '')) as TagsLength,
    coalesce(cqa.BadgeCount,0) * 10 + coalesce(cqa.AnswerCount,0) * 5 + coalesce(cqa.ViewCount,0)/100 as CompositeScore
from ComplexQuestionAnalysis cqa
where cqa.CreationDate > now() - interval '1 year'
order by CompositeScore desc, cqa.Score desc, cqa.ViewCount desc
limit 50;