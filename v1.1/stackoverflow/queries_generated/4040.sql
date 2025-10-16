-- {"query": "4040.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1647} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.Score as QuestionScore,
        p.ViewCount as QuestionViews,
        p.CreationDate as QuestionCreation,
        u.Reputation as OwnerReputation,
        u.Id as OwnerUserId,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.PostTypeId = 1 and (p.Tags like '%' || t.TagName || '%')
    left join Users u on u.Id = p.OwnerUserId
),
FilteredTags as (
    select 
        Id, TagName, Count, AnswerCount, QuestionScore, QuestionViews, QuestionCreation, OwnerReputation, OwnerUserId
    from RecursiveTagCounts
    where rn = 1
),
UserBadgeAgg as (
    select
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PopularAnswerStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwner,
        u.Reputation as AnswererReputation,
        v.UpVotes,
        v.DownVotes,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    left join (
        select
            p.Id,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        join Posts p on p.Id = v.PostId
        group by p.Id
    ) v on v.Id = a.Id
    where a.PostTypeId = 2
),
QuestionAnswerSummary as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        u.DisplayName as QuestionOwner,
        u.Reputation as OwnerReputation,
        psa.AnswerId,
        psa.AnswerScore,
        psa.AnswerOwner,
        psa.AnswererReputation,
        psa.UpVotes,
        psa.DownVotes
    from Posts q
    left join Users u on u.Id = q.OwnerUserId
    left join PopularAnswerStats psa on psa.QuestionId = q.Id and psa.AnswerRank = 1
    where q.PostTypeId = 1 and q.ClosedDate is null
),
PostHistoryEditCounts as (
    select
        ph.PostId,
        count(*) FILTER (WHERE ph.PostHistoryTypeId in (4,5,6)) as TitleBodyTagEdits,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
),
PostCommentAggregates as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.UserId is null then 0 else 1 end) as UserComments,
        string_agg(distinct coalesce(u.DisplayName,c.UserDisplayName), ', ' order by coalesce(u.DisplayName,c.UserDisplayName)) as Commenters
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        lag(u.LastAccessDate) over (partition by u.Id order by u.LastAccessDate) as PrevAccessDate,
        extract(epoch from (u.LastAccessDate - lag(u.LastAccessDate) over (partition by u.Id order by u.LastAccessDate)))/3600 as HoursBetweenAccesses
    from Users u
),
DuplicateQuestions as (
    select distinct pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
),
FinalResultSet as (
    select
        qas.QuestionId,
        qas.Title,
        qas.QuestionScore,
        qas.ViewCount,
        qas.Tags,
        qas.QuestionOwner,
        qas.OwnerReputation,
        qas.AnswerId,
        qas.AnswerScore,
        qas.AnswerOwner,
        qas.AnswererReputation,
        qas.UpVotes,
        qas.DownVotes,
        ph.CountTitleBodyTagEdits,
        ph.LastEditDate,
        pc.CommentCount,
        pc.UserComments,
        pc.Commenters,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        dt.OriginalQuestionId,
        case when dt.OriginalQuestionId is not null then true else false end as IsDuplicate
    from QuestionAnswerSummary qas
    left join PostHistoryEditCounts ph on ph.PostId = qas.QuestionId
    left join PostCommentAggregates pc on pc.PostId = qas.QuestionId
    left join UserBadgeAgg ua on ua.UserId = (select OwnerUserId from Posts where Id = qas.QuestionId)
    left join DuplicateQuestions dt on dt.DuplicateQuestionId = qas.QuestionId
)
select 
    fr.*,
    concat(
        'Q: ', fr.Title, ' (Score: ', fr.QuestionScore::text, ', Views: ', fr.ViewCount::text, ') - ',
        'Asked by ', coalesce(fr.QuestionOwner, 'Unknown'), ' (Rep: ', coalesce(fr.OwnerReputation::text, '0'), ')',
        case when fr.IsDuplicate then concat(' [DUPLICATE of Q#', fr.OriginalQuestionId::text, '] ') else ' ' end,
        'Top Answer: ', coalesce(fr.AnswerOwner, 'N/A'), ' (Score: ', coalesce(fr.AnswerScore::text, '0'), ', Up:', coalesce(fr.UpVotes::text, '0'), ', Down:', coalesce(fr.DownVotes::text, '0'), ')',
        '. Comments (', fr.CommentCount::text, ', Users: ', fr.UserComments::text, '): ', coalesce(fr.Commenters, 'No comments'),
        '. Edits: ', coalesce(fr.CountTitleBodyTagEdits::text, '0'), ' (Last edit: ', coalesce(fr.LastEditDate::text, 'Never'), ')',
        '. Owner Badges - Gold: ', coalesce(fr.GoldBadges::text, '0'), ', Silver: ', coalesce(fr.SilverBadges::text, '0'), ', Bronze: ', coalesce(fr.BronzeBadges::text, '0')
    ) as FullDescription
from FinalResultSet fr
where fr.OwnerReputation > 1000
order by fr.QuestionScore desc, fr.ViewCount desc, fr.AnswerScore desc
limit 50;