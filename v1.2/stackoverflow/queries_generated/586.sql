-- {"query": "586.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1736} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join PostLinks pl on pl.PostId = t.ExcerptPostId
    join RecursiveTagHierarchy r on pl.RelatedPostId = r.Id
    where t.IsModeratorOnly = 0 and not t.TagName = any(r.Path)
    and r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(v.VoteTypeId = 2::int)::int,0) as UpVotesReceived,
        coalesce(sum(v.VoteTypeId = 3::int)::int,0) as DownVotesReceived,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        (extract(epoch from max(p.CreationDate)) - extract(epoch from min(p.CreationDate))) / 86400.0 as ActiveDaysSpan
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
PostScoresWithRank as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreDenseRank
    from Posts p
    where p.PostTypeId in (1,2)
),
CorrelatedAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        a.CreationDate as AcceptedAnswerDate
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
BadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    group by b.UserId
),
TopTagsByQuestionCount as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as QuestionCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by QuestionCount desc
    limit 10
),
UserTagEngagement as (
    select
        u.Id as UserId,
        t.TagName,
        count(p.Id) as PostsInTag,
        avg(p.Score) as AvgScoreInTag,
        max(p.CreationDate) as LastPostInTag
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as t(TagName)
    group by u.Id, t.TagName
),
UserActivityWithBadges as (
    select
        ua.*,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges,
        coalesce(bc.DistinctBadges,0) as DistinctBadges
    from UserActivity ua
    left join BadgeCounts bc on ua.UserId = bc.UserId
),
FinalUserStats as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.DistinctBadges,
        ua.LastPostDate,
        ua.FirstPostDate,
        ua.ActiveDaysSpan,
        case when ua.ActiveDaysSpan > 0 then (ua.QuestionsPosted + ua.AnswersPosted)::float / ua.ActiveDaysSpan else null end as AvgPostsPerDay,
        case when ua.QuestionsPosted > 0 then ua.AnswersPosted::float / ua.QuestionsPosted else null end as AnswerToQuestionRatio
    from UserActivityWithBadges ua
    where ua.QuestionsPosted + ua.AnswersPosted + ua.CommentsMade > 50
)
select
    fus.UserId,
    fus.DisplayName,
    fus.QuestionsPosted,
    fus.AnswersPosted,
    fus.CommentsMade,
    fus.UpVotesReceived,
    fus.DownVotesReceived,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.DistinctBadges,
    fus.LastPostDate,
    fus.FirstPostDate,
    round(fus.ActiveDaysSpan,2) as ActiveDaysSpanDays,
    round(fus.AvgPostsPerDay,4) as AvgPostsPerDay,
    round(fus.AnswerToQuestionRatio,4) as AnswerToQuestionRatio,
    ut.TagName as MostEngagedTag,
    ut.PostsInTag,
    round(ut.AvgScoreInTag,2) as AvgScoreInTag,
    ut.LastPostInTag,
    pt.ScoreRank,
    pt.ScoreDenseRank,
    coalesce(ca.AcceptedAnswerScore,0) as AcceptedAnswerScore,
    coalesce(pl.LinkCount,0) as TotalPostLinks,
    case when p.ClosedDate is not null then 'Closed' else 'Open' end as PostStatus,
    ph.PostHistoryEdits
from FinalUserStats fus
left join lateral (
    select ut1.TagName, ut1.PostsInTag, ut1.AvgScoreInTag, ut1.LastPostInTag
    from UserTagEngagement ut1
    where ut1.UserId = fus.UserId
    order by ut1.PostsInTag desc nulls last, ut1.AvgScoreInTag desc nulls last
    limit 1
) ut on true
left join Posts p on p.OwnerUserId = fus.UserId and p.PostTypeId = 1
left join PostScoresWithRank pt on pt.Id = p.Id
left join CorrelatedAcceptedAnswers ca on ca.QuestionId = p.Id
left join (
    select pl.PostId, count(*) as LinkCount
    from PostLinks pl
    group by pl.PostId
) pl on pl.PostId = p.Id
left join (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as PostHistoryEdits
    from PostHistory ph
    group by ph.PostId
) ph on ph.PostId = p.Id
where fus.GoldBadges > 0 or fus.AnswersPosted > 100
order by fus.GoldBadges desc, fus.AnswersPosted desc, fus.UpVotesReceived desc
limit 100;