-- {"query": "447.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1685} 
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
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        r.Level + 1,
        r.Path || child.Id
    from Tags child
    join RecursiveTagHierarchy r on child.Id != all(r.Path)
    where child.IsRequired = 1
      and child.Count < r.Count
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges,
        row_number() over (partition by u.Id order by b.Date desc nulls last) as LatestBadgeRank,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreWindows as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        avg(p.Score) over (partition by p.PostTypeId order by p.CreationDate rows between 30 preceding and current row) as AvgScoreLast30,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.ViewCount desc) as ViewRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > q.Score then 1 else 0 end) as AnswersBetterThanQuestion,
        string_agg(distinct u.DisplayName, ', ') filter (where u.DisplayName is not null) as AnswererNames
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount
    having count(a.Id) > 0
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes chtt on ph.PostHistoryTypeId = chtt.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
TopTagsByPopularity as (
    select
        t.TagName,
        t.Count,
        coalesce(pq.QuestionCount,0) as QuestionCount,
        coalesce(pa.AnswerCount,0) as AnswerCount,
        coalesce(avg(q.Score),0) as AvgQuestionScore,
        coalesce(avg(a.Score),0) as AvgAnswerScore
    from Tags t
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
            count(*) as QuestionCount
        from Posts p
        where p.PostTypeId = 1
        group by Tag
    ) pq on pq.Tag = t.TagName
    left join (
        select
            unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as Tag,
            count(a.Id) as AnswerCount
        from Posts a
        join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
        where a.PostTypeId = 2
        group by Tag
    ) pa on pa.Tag = t.TagName
    left join Posts q on q.PostTypeId = 1 and position('<' || t.TagName || '>' in q.Tags) > 0
    left join Posts a on a.PostTypeId = 2 and a.ParentId = q.Id
    group by t.TagName, t.Count, pq.QuestionCount, pa.AnswerCount
    order by t.Count desc nulls last
    limit 50
)
select
    u.DisplayName as User,
    u.QuestionsPosted,
    u.AnswersPosted,
    u.CommentsMade,
    u.UpVotesReceived,
    u.DownVotesReceived,
    u.TotalPostScore,
    u.LastPostDate,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    q.QuestionId,
    q.Title as QuestionTitle,
    q.QuestionDate,
    q.QuestionScore,
    q.QuestionViews,
    q.AnswerCount,
    q.MaxAnswerScore,
    q.AvgAnswerScore,
    q.AnswersBetterThanQuestion,
    q.AnswererNames,
    c.CloseReason,
    c.CloseCount,
    t.TagName,
    t.Count as TagUsageCount,
    t.QuestionCount as TagQuestionCount,
    t.AnswerCount as TagAnswerCount,
    t.AvgQuestionScore as TagAvgQuestionScore,
    t.AvgAnswerScore as TagAvgAnswerScore
from UserActivitySummary u
left join UserBadgeStats ub on ub.UserId = u.Id and ub.LatestBadgeRank = 1
left join TopQuestionsWithAnswers q on q.OwnerUserId = u.Id
left join CloseReasonCounts c on true
left join TopTagsByPopularity t on true
where u.QuestionsPosted > 10
  and u.AnswersPosted > 5
  and (ub.GoldBadges + ub.SilverBadges + ub.BronzeBadges) > 3
  and q.AnswersBetterThanQuestion > 0
  and (t.QuestionCount > 100 or t.AnswerCount > 200)
order by u.TotalPostScore desc, q.QuestionScore desc, t.Count desc
limit 100;