-- {"query": "2791.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1405} 
with RecursiveQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        coalesce(array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'),1),0) as TagCount,
        p.AcceptedAnswerId
    from
        Posts p
    where
        p.PostTypeId = 1
        and p.CreationDate >= (current_timestamp - interval '1 year')
),
AcceptedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.Reputation as AnswererReputation,
        u.DisplayName as AnswererName,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as UpVotesCount,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as DownVotesCount,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from
        Posts a
        left join Users u on a.OwnerUserId = u.Id
    where
        a.PostTypeId = 2
),
PostCommentsAggregated as (
    select
        c.PostId,
        count(*) filter (where c.Score >= 5) as HighScoreComments,
        bool_or(c.Text ilike '%performance%') as HasPerformanceComment,
        max(c.CreationDate) as LastCommentDate
    from
        Comments c
    group by
        c.PostId
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased = 1) as HasTagBadges,
        max(b.Date) as LastBadgeDate
    from
        Badges b
    group by
        b.UserId
),
CloseVoteCounts as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotes
    from
        PostHistory ph
    group by
        ph.PostId
),
LinksCounts as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedPostsCount,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinksCount
    from
        PostLinks pl
    group by
        pl.PostId
),
QuestionPerformance as (
    select
        rq.Id as QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.CreationDate as QuestionCreationDate,
        rq.Score as QuestionScore,
        rq.ViewCount,
        rq.AnswerCount,
        rq.TagCount,
        rq.AcceptedAnswerId,
        aa.Id as AcceptedAnswerId,
        aa.AnswerScore,
        aa.AnswerCreationDate,
        aa.AnswererReputation,
        aa.AnswererName,
        aa.UpVotesCount,
        aa.DownVotesCount,
        pc.HighScoreComments,
        pc.HasPerformanceComment,
        pc.LastCommentDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.HasTagBadges,
        ub.LastBadgeDate,
        cv.CloseVotes,
        cv.ReopenVotes,
        lc.LinkedPostsCount,
        lc.DuplicateLinksCount,
        rank() over (order by rq.Score desc, rq.ViewCount desc) as QuestionPopularRank
    from
        RecursiveQuestions rq
        left join AcceptedAnswers aa on rq.AcceptedAnswerId = aa.Id
        left join PostCommentsAggregated pc on rq.Id = pc.PostId
        left join UserBadgeSummary ub on rq.OwnerUserId = ub.UserId
        left join CloseVoteCounts cv on rq.Id = cv.PostId
        left join LinksCounts lc on rq.Id = lc.PostId
)
select
    QuestionId,
    concat_ws(' - ', left(Title, 40), coalesce(AnswererName, 'No accepted answer')) as QuestionSummary,
    QuestionCreationDate,
    QuestionScore,
    ViewCount,
    AnswerCount,
    TagCount,
    coalesce(AcceptedAnswerId, 0) as AcceptedAnswerId,
    coalesce(AnswerScore, 0) as AcceptedAnswerScore,
    coalesce(AnswerCreationDate, to_timestamp(0)) as AcceptedAnswerCreationDate,
    coalesce(AnswererReputation, 0) as AnswererReputation,
    UpVotesCount,
    DownVotesCount,
    HighScoreComments,
    HasPerformanceComment,
    LastCommentDate,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    HasTagBadges,
    LastBadgeDate,
    CloseVotes,
    ReopenVotes,
    LinkedPostsCount,
    DuplicateLinksCount,
    QuestionPopularRank,
    /* Complex null-safe calculation combining score and badges */
    case
        when QuestionScore is null then 0
        else
            QuestionScore *
            (1 + coalesce(GoldBadges,0)*0.5 + coalesce(SilverBadges,0)*0.3 + coalesce(BronzeBadges,0)*0.1) /
            nullif(TagCount,0)
    end as AdjustedScore,
    /* An expression mixing string functions and conditional logic */
    case
        when HasPerformanceComment then upper(concat('‼ ', left(Title, 50), ' ‼'))
        else lower(Title)
    end as TitleHighlight,
    /* Window function demonstrating lag with null-safe defaults */
    coalesce(lag(QuestionScore) over (order by QuestionCreationDate),0) as PrevQuestionScore,
    /* Correlated subquery for counting answers posted after this question */
    (
        select count(*)
        from Posts p2
        where p2.PostTypeId = 2
          and p2.ParentId = RecursiveQuestions.Id
          and p2.CreationDate > RecursiveQuestions.CreationDate
    ) as AnswersAfterQuestionCreation
from
    QuestionPerformance qp
join RecursiveQuestions on qp.QuestionId = RecursiveQuestions.Id
order by
    AdjustedScore desc,
    QuestionCreationDate desc
limit 100;