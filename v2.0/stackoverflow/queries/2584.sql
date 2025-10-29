-- {"query": "2584.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1633}
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.Date as BadgeDate,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where (b.TagBased = false) or b.TagBased is null
),
LatestBadges as (
    select UserId, DisplayName, BadgeName, BadgeClass, BadgeDate
    from RecursiveUserBadges
    where rn <= 3
),
PostScoreRank as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.PostTypeId,
        p.CreationDate,
        rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        count(*) as TotalPosts,
        count(case when p.PostTypeId = 1 then 1 end) as TotalQuestions,
        count(case when p.PostTypeId = 2 then 1 end) as TotalAnswers,
        avg(p.Score) as AvgPostScore,
        sum(p.ViewCount) as TotalViews,
        max(p.CreationDate) as LatestPostDate,
        sum(case when p.ClosedDate is not null then 1 else 0 end) as ClosedQuestionsCount,
        max(case when p.PostTypeId = 1 then p.Score end) as MaxQuestionScore,
        max(case when p.PostTypeId = 2 then p.Score end) as MaxAnswerScore
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId
),
TopRelatedTags as (
    select
        p.OwnerUserId,
        t.tag,
        count(*) as TagCount,
        rank() over (partition by p.OwnerUserId order by count(*) desc) as TagRank
    from Posts p,
         lateral (
           select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
         ) t
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags != ''
    group by p.OwnerUserId, t.tag
),
FilteredTopRelatedTags as (
    select OwnerUserId, tag
    from TopRelatedTags
    where TagRank <= 2
),
AnsweredQuestionsWithAcceptedAnswer as (
    select
        q.Id as QuestionId,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        q.AcceptedAnswerId
    from Posts q
    join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1 and a.PostTypeId = 2
),
UserAnswerStats as (
    select
        a.AnswerOwner as UserId,
        count(*) as AcceptedAnswersCount,
        avg(a.AnswerScore) as AvgAcceptedAnswerScore
    from AnsweredQuestionsWithAcceptedAnswer a
    group by a.AnswerOwner
),
CloseReasonsCount as (
    select
        ph.UserId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10 and ph.UserId is not null
    group by ph.UserId, crt.Name
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(ps.TotalPosts, 0) as TotalPosts,
        coalesce(ps.TotalQuestions, 0) as TotalQuestions,
        coalesce(ps.TotalAnswers, 0) as TotalAnswers,
        coalesce(ps.AvgPostScore, 0) as AvgPostScore,
        coalesce(ps.TotalViews, 0) as TotalViews,
        coalesce(ua.AcceptedAnswersCount, 0) as AcceptedAnswersCount,
        coalesce(ua.AvgAcceptedAnswerScore, 0) as AvgAcceptedAnswerScore,
        string_agg(distinct ft.tag, ', ' order by ft.tag) as TopTags,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2) as TotalUpVotesGiven,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3) as TotalDownVotesGiven,
        coalesce(cc.CloseCount, 0) as CloseVotesCast
    from Users u
    left join UserPostStats ps on u.Id = ps.UserId
    left join UserAnswerStats ua on u.Id = ua.UserId
    left join FilteredTopRelatedTags ft on u.Id = ft.OwnerUserId
    left join (
        select UserId, sum(CloseCount) as CloseCount
        from CloseReasonsCount
        group by UserId
    ) cc on u.Id = cc.UserId
    group by u.Id, u.DisplayName, ps.TotalPosts, ps.TotalQuestions, ps.TotalAnswers, ps.AvgPostScore, ps.TotalViews, ua.AcceptedAnswersCount, ua.AvgAcceptedAnswerScore, cc.CloseCount
),
TopPostsAndComments as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        c.Id as CommentId,
        c.Score as CommentScore,
        c.Text as CommentText
    from Posts p
    left join lateral (
        select ctmp.Id, ctmp.PostId, ctmp.Score, ctmp.CreationDate, ctmp.Text
        from Comments ctmp
        where ctmp.PostId = p.Id
        order by ctmp.Score desc, ctmp.CreationDate asc
        limit 1
    ) c on true
    where p.PostTypeId = 1
),
RankingWithWindows as (
    select
        uas.UserId,
        uas.DisplayName,
        uas.TotalPosts,
        uas.TotalQuestions,
        uas.TotalAnswers,
        uas.AvgPostScore,
        uas.TotalViews,
        uas.AcceptedAnswersCount,
        uas.AvgAcceptedAnswerScore,
        uas.TopTags,
        uas.TotalUpVotesGiven,
        uas.TotalDownVotesGiven,
        uas.CloseVotesCast,
        pnc.PostId as TopPostId,
        pnc.Title as TopPostTitle,
        pnc.Score as TopPostScore,
        pnc.ViewCount as TopPostViews,
        pnc.CommentId,
        pnc.CommentScore,
        pnc.CommentText,
        row_number() over (order by uas.TotalPosts desc, uas.TotalViews desc) as UserRank
    from UserActivitySummary uas
    left join TopPostsAndComments pnc on uas.UserId = pnc.OwnerUserId
    where uas.TotalPosts > 50
)
select
    UserRank,
    UserId,
    DisplayName,
    TotalPosts,
    TotalQuestions,
    TotalAnswers,
    round(CAST(AvgPostScore AS numeric), 2) as AvgPostScore,
    TotalViews,
    AcceptedAnswersCount,
    round(CAST(AvgAcceptedAnswerScore AS numeric), 2) as AvgAcceptedAnswerScore,
    coalesce(TopTags, '(none)') as TopTags,
    TotalUpVotesGiven,
    TotalDownVotesGiven,
    CloseVotesCast,
    TopPostId,
    TopPostTitle,
    TopPostScore,
    TopPostViews,
    CommentId,
    CommentScore,
    case when CommentText is null then null else substring(CommentText from 1 for 100) || case when char_length(CommentText) > 100 then '...' else '' end end as CommentPreview
from RankingWithWindows
where UserRank <= 10
order by UserRank;