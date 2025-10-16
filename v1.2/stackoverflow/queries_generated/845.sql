-- {"query": "845.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2102} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, b.Class
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2) -- Questions and Answers
),
LatestPostHistoryPerPost AS (
    select ph1.*
    from PostHistory ph1
    inner join (
        select PostId, max(CreationDate) as MaxDate
        from PostHistory
        group by PostId
    ) ph2 on ph1.PostId = ph2.PostId and ph1.CreationDate = ph2.MaxDate
),
PostCloseReasons AS (
    select
        ph.PostId,
        crt.Name as CloseReasonName
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10  -- Post Closed
),
UserActivityStats AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        sum(v.VoteTypeScore) as VoteScoreSum
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            v.PostId,
            case
                when vt.Name = 'UpMod' then 1
                when vt.Name = 'DownMod' then -1
                else 0
            end as VoteTypeScore
        from Votes v
        inner join VoteTypes vt on v.VoteTypeId = vt.Id
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
QuestionsWithAcceptedAnswers AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerCreationDate,
        u.DisplayName as QuestionOwnerName,
        au.DisplayName as AcceptedAnswerOwnerName,
        (a.CreationDate - q.CreationDate) as TimeToAcceptInterval
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on q.OwnerUserId = u.Id
    left join Users au on a.OwnerUserId = au.Id
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
TagAnalysis AS (
    select
        t.Id as TagId,
        t.TagName,
        t.Count as TagCount,
        coalesce(qc.QuestionCount, 0) as QuestionCount,
        coalesce(ac.AnswerCount, 0) as AnswerCount,
        coalesce(avgq.AvgQuestionScore, 0) as AvgQuestionScore,
        coalesce(avga.AvgAnswerScore, 0) as AvgAnswerScore
    from Tags t
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
            count(p.Id) as QuestionCount
        from Posts p
        where p.PostTypeId = 1
        group by TagName
    ) qc on qc.TagName = t.TagName
    left join (
        select
            unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as TagName,
            count(a.Id) as AnswerCount
        from Posts q
        join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        where q.PostTypeId = 1
        group by TagName
    ) ac on ac.TagName = t.TagName
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
            avg(p.Score) as AvgQuestionScore
        from Posts p
        where p.PostTypeId = 1
        group by TagName
    ) avgq on avgq.TagName = t.TagName
    left join (
        select
            unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as TagName,
            avg(a.Score) as AvgAnswerScore
        from Posts q
        join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        where q.PostTypeId = 1
        group by TagName
    ) avga on avga.TagName = t.TagName
)
select
    r.PostTypeId,
    r.Id as PostId,
    r.Title,
    r.Score,
    r.ViewCount,
    r.ScoreRank,
    r.CreationDate,
    coalesce(u.DisplayName, 'Community') as OwnerName,
    coalesce(bc.BadgeCount, 0) as GoldBadges,
    coalesce(bc2.BadgeCount, 0) as SilverBadges,
    coalesce(bc3.BadgeCount, 0) as BronzeBadges,
    pcr.CloseReasonName,
    ph.CreationDate as LastHistoryEditDate,
    ph.PostHistoryTypeId,
    ph.Comment as HistoryComment,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.MaxQuestionScore,
    uas.AvgAnswerScore,
    uas.VoteScoreSum,
    qaa.AcceptedAnswerId,
    qaa.AcceptedAnswerScore,
    qaa.TimeToAcceptInterval,
    ta.TagName,
    ta.TagCount,
    ta.QuestionCount as TagQuestions,
    ta.AnswerCount as TagAnswers,
    ta.AvgQuestionScore as TagAvgQuestionScore,
    ta.AvgAnswerScore as TagAvgAnswerScore,
    case
        when r.Score > 100 then 'Hot'
        when r.Score between 50 and 100 then 'Trending'
        else 'Normal'
    end as PopularityCategory,
    concat_ws(' | ', r.Title, coalesce(pcr.CloseReasonName, 'Open')) as TitleWithStatus,
    row_number() over (partition by r.PostTypeId order by r.Score desc, r.ViewCount desc) as PostRowNum
from RankedPosts r
left join Users u on u.Id = r.OwnerUserId
left join RecursiveUserBadgeCounts bc on bc.UserId = u.Id and bc.Class = 1
left join RecursiveUserBadgeCounts bc2 on bc2.UserId = u.Id and bc2.Class = 2
left join RecursiveUserBadgeCounts bc3 on bc3.UserId = u.Id and bc3.Class = 3
left join PostCloseReasons pcr on pcr.PostId = r.Id
left join LatestPostHistoryPerPost ph on ph.PostId = r.Id
left join UserActivityStats uas on uas.UserId = r.OwnerUserId
left join QuestionsWithAcceptedAnswers qaa on qaa.QuestionId = r.Id
left join lateral (
    select t.TagName, t.Count as TagCount, qc.QuestionCount, ac.AnswerCount, avgq.AvgQuestionScore, avga.AvgAnswerScore
    from Tags t
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
            count(p.Id) as QuestionCount
        from Posts p
        where p.PostTypeId = 1
        group by TagName
    ) qc on qc.TagName = t.TagName
    left join (
        select
            unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as TagName,
            count(a.Id) as AnswerCount
        from Posts q
        join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        where q.PostTypeId = 1
        group by TagName
    ) ac on ac.TagName = t.TagName
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName,
            avg(p.Score) as AvgQuestionScore
        from Posts p
        where p.PostTypeId = 1
        group by TagName
    ) avgq on avgq.TagName = t.TagName
    left join (
        select
            unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as TagName,
            avg(a.Score) as AvgAnswerScore
        from Posts q
        join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
        where q.PostTypeId = 1
        group by TagName
    ) avga on avga.TagName = t.TagName
    where t.TagName = any(string_to_array(substring(r.Tags from 2 for length(r.Tags)-2), '><'))
    limit 1
) ta on true
where r.ScoreRank <= 100
order by r.PostTypeId, r.Score desc, r.ViewCount desc
limit 200;