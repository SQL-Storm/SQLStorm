-- {"query": "2670.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1585} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.Id] as AncestorPath
    from Tags t
    where t.IsRequired = 1

    union all

    select
        c.Id,
        c.TagName,
        c.Count,
        r.AncestorPath || c.Id
    from Tags c
    join PostLinks pl on pl.PostId = c.ExcerptPostId
    join RecursiveTagHierarchy r on r.Id = pl.RelatedPostId
    where c.Id <> all(r.AncestorPath)
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(vp.Score), 0) as TotalPostScore,
        avg(case when p.PostTypeId in (1,2) then p.Score else null end) as AvgPostScore,
        count(distinct b.Id) as BadgeCount,
        max(b.Date) as LastBadgeDate,
        bool_or(b.TagBased) as HasTagBasedBadge,
        max(p.ViewCount) filter (where p.PostTypeId = 1) as MaxQuestionViews
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes vp on vp.PostId = p.Id and vp.VoteTypeId = 2
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopScoringAnswers as (
    select
        p.Id,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as rn
    from Posts p
    where p.PostTypeId = 2
),
SelectedAnswers as (
    select
        tsa.ParentId as QuestionId,
        tsa.Id as AnswerId,
        tsa.OwnerUserId as AnswerUserId,
        tsa.Score as AnswerScore
    from TopScoringAnswers tsa
    where tsa.rn = 1
),
QuestionWithAcceptedAnswer as (
    select
        q.Id,
        q.Title,
        q.Tags,
        q.CreationDate,
        q.AcceptedAnswerId,
        q.OwnerUserId,
        sq.AnswerId as TopAnswerId,
        sq.AnswerUserId as TopAnswerUserId,
        sq.AnswerScore as TopAnswerScore,
        uqs.DisplayName as QuestionOwner,
        uans.DisplayName as TopAnswerOwner
    from Posts q
    left join SelectedAnswers sq on sq.QuestionId = q.Id
    left join Users uqs on uqs.Id = q.OwnerUserId
    left join Users uans on uans.Id = sq.AnswerUserId
    where q.PostTypeId = 1
),
TagAgg as (
    select
        unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags) - 2), '><')) as TagName,
        q.Id as QuestionId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null
),
TagStats as (
    select
        ta.TagName,
        count(distinct ta.QuestionId) as QuestionsCount,
        avg(ta.QuestionScore) as AvgScore,
        sum(ta.QuestionViews) as TotalViews,
        max(ta.QuestionScore) as MaxScore
    from TagAgg ta
    group by ta.TagName
),
UserBadgeRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        rank() over (order by count(b.Id) desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
CommentsWithSentiment as (
    select
        c.Id,
        c.PostId,
        c.Score,
        c.Text,
        length(c.Text) as TextLength,
        case
            when position('?' in c.Text) > 0 then 1
            else 0
        end as ContainsQuestion,
        case
            when c.Text ILIKE '%thank%' or c.Text ILIKE '%thanks%' then 1
            else 0
        end as ContainsThanks
    from Comments c
),
PostCloseHistory as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastCloseDate,
        bool_or(ph.PostHistoryTypeId = 10) as IsClosed
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
)
select
    qwa.Id as QuestionId,
    qwa.Title,
    qwa.CreationDate,
    qwa.QuestionOwner,
    qwa.TopAnswerId,
    qwa.TopAnswerUserId,
    qwa.TopAnswerScore,
    statsReputation.Reputation,
    ubs.BadgeCount,
    ubs.HasTagBasedBadge,
    ts.QuestionsCount,
    ts.AvgScore,
    ts.TotalViews,
    phh.IsClosed,
    phh.LastCloseDate,
    avg(cws.ContainsQuestion) over (partition by qwa.Id) as QuestionCommentQuestionRatio,
    string_agg(distinct concat_ws(':', u.DisplayName, b.Name), ', ') as UserBadgePairs,
    dense_rank() over (order by qwa.TopAnswerScore desc, qwa.CreationDate) as AnswerScoreRank,
    concat(left(qwa.Title, 30), '...', ' [', coalesce(to_char(qwa.CreationDate, 'YYYY'), 'NA'), ']') as ShortTitleYear,
    case
        when qwa.TopAnswerScore > qwa.Score then 'Top answer outperforms question'
        when qwa.TopAnswerScore = qwa.Score then 'Top answer ties question'
        else 'Question leads'
    end as PerformanceComparison,
    coalesce(qwa.Tags, 'NoTags') as TagsCollapsed
from QuestionWithAcceptedAnswer qwa
inner join UserPostStats statsReputation on statsReputation.UserId = qwa.OwnerUserId
left join UserPostStats ubs on ubs.UserId = qwa.TopAnswerUserId
left join TagStats ts on ts.TagName = any(string_to_array(substring(qwa.Tags from 2 for length(qwa.Tags)-2), '><'))
left join PostCloseHistory phh on phh.PostId = qwa.Id
left join CommentsWithSentiment cws on cws.PostId = qwa.Id
left join Badges b on b.UserId = qwa.OwnerUserId
left join Users u on u.Id = b.UserId
where qwa.CreationDate >= (current_date - interval '365 days')
group by qwa.Id, qwa.Title, qwa.CreationDate, qwa.QuestionOwner, qwa.TopAnswerId, qwa.TopAnswerUserId, qwa.TopAnswerScore,
    statsReputation.Reputation, ubs.BadgeCount, ubs.HasTagBasedBadge, ts.QuestionsCount, ts.AvgScore, ts.TotalViews,
    phh.IsClosed, phh.LastCloseDate, qwa.Score, qwa.Tags
order by AnswerScoreRank, qwa.CreationDate desc
limit 100;