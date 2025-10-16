-- {"query": "658.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1467} 
with RecursiveUserPosts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
), RankedAnswers as (
    select 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.CreationDate,
        u.DisplayName as AnswerOwner,
        dense_rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 2
), QuestionWithAcceptedAnswer as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        a.AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.AnswerOwner
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
), CloseReasonCounts as (
    select
        cht.Name as CloseReasonName,
        count(distinct ph.PostId) as ClosedPostsCount
    from PostHistory ph
    join PostHistoryTypes chtype on ph.PostHistoryTypeId = chtype.Id
    join CloseReasonTypes cht on ph.Comment::int = cht.Id
    where ph.PostHistoryTypeId = 10
    group by cht.Name
), UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
), UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join UserBadgeCounts bc on bc.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
), TopTagUsage as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag,
        count(*) as UsageCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    order by UsageCount desc
    limit 10
), PostsWithLinkInfo as (
    select 
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        coalesce(pl.LinkCount,0) as LinkCount,
        coalesce(dl.DuplicateCount,0) as DuplicateCount
    from Posts p
    left join (
        select PostId, count(*) as LinkCount
        from PostLinks
        group by PostId
    ) pl on pl.PostId = p.Id
    left join (
        select PostId, count(*) as DuplicateCount
        from PostLinks
        where LinkTypeId = 3
        group by PostId
    ) dl on dl.PostId = p.Id
)
select 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.QuestionsPosted,
    uas.AnswersPosted,
    uas.CommentsMade,
    uas.MaxQuestionScore,
    uas.MaxAnswerScore,
    qwa.QuestionId,
    qwa.Title as QuestionTitle,
    qwa.QuestionScore,
    qwa.ViewCount as QuestionViewCount,
    qwa.AnswerId,
    qwa.AnswerScore,
    qwa.AnswerCreationDate,
    qwa.AnswerOwner,
    crc.CloseReasonName,
    crc.ClosedPostsCount,
    ttu.Tag as PopularTag,
    ttu.UsageCount as TagUsage,
    pwli.LinkCount,
    pwli.DuplicateCount,
    -- Complex string expression: concatenation and conditional substring extraction with NULL logic
    case 
        when position('sql' in lower(qwa.Title)) > 0 then 
            substring(qwa.Title from position('sql' in lower(qwa.Title)) for 10) || '...'
        else 
            coalesce(qwa.Title, 'No Title')
    end as SnippetTitle,
    -- Window function: rank answers by score per question
    ran.AnswerRank
from UserActivitySummary uas
left join QuestionWithAcceptedAnswer qwa on qwa.AnswerOwner = uas.DisplayName
left join CloseReasonCounts crc on crc.CloseReasonName = (
    select cht.Name 
    from PostHistory ph2
    join CloseReasonTypes cht on ph2.Comment::int = cht.Id
    where ph2.PostId = qwa.QuestionId and ph2.PostHistoryTypeId = 10
    order by ph2.CreationDate desc limit 1
)
left join TopTagUsage ttu on ttu.Tag = any(string_to_array(substring(qwa.Tags from 2 for char_length(qwa.Tags)-2), '><'))
left join PostsWithLinkInfo pwli on pwli.PostId = qwa.QuestionId
left join RankedAnswers ran on ran.AnswerId = qwa.AnswerId
where uas.Reputation > 2000
order by uas.Reputation desc, qwa.QuestionScore desc
limit 100;