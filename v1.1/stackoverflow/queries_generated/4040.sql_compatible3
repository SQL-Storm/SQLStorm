with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        p.Score as QuestionScore,
        p.ViewCount as QuestionViews,
        p.CreationDate as QuestionCreation,
        u.Reputation as OwnerReputation,
        u.Id as OwnerUserId,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like '%' || t.TagName || '%'
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
        count(case when b.Class = 1 then 1 end) AS GoldBadges,
        count(case when b.Class = 2 then 1 end) AS SilverBadges,
        count(case when b.Class = 3 then 1 end) AS BronzeBadges,
        max(b.Date) as LastBadgeDate
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
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
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
        count(case when ph.PostHistoryTypeId in (4,5,6) then 1 end) as TitleBodyTagEdits,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
),
PostCommentAggregates as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.UserId is null then 0 else 1 end) as UserComments,
        -- string_agg with distinct and order by is not available in all dialects; emulate with listagg / group_concat fallback
        -- Use ANSI LISTAGG where available; here provide a generic aggregate using string_agg without distinct
        string_agg(coalesce(u.DisplayName, c.UserDisplayName), ', ') as Commenters
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
        coalesce(ph.TitleBodyTagEdits, 0) as CountTitleBodyTagEdits,
        ph.LastEditDate,
        coalesce(pc.CommentCount, 0) as CommentCount,
        coalesce(pc.UserComments, 0) as UserComments,
        pc.Commenters,
        coalesce(ua.GoldBadges, 0) as GoldBadges,
        coalesce(ua.SilverBadges, 0) as SilverBadges,
        coalesce(ua.BronzeBadges, 0) as BronzeBadges,
        dt.OriginalQuestionId,
        case when dt.OriginalQuestionId is not null then true else false end as IsDuplicate
    from QuestionAnswerSummary qas
    left join PostHistoryEditCounts ph on ph.PostId = qas.QuestionId
    left join PostCommentAggregates pc on pc.PostId = qas.QuestionId
    left join UserBadgeAgg ua on ua.UserId = (select p2.OwnerUserId from Posts p2 where p2.Id = qas.QuestionId)
    left join DuplicateQuestions dt on dt.DuplicateQuestionId = qas.QuestionId
)
select 
    fr.QuestionId,
    fr.Title,
    fr.QuestionScore,
    fr.ViewCount,
    fr.Tags,
    fr.QuestionOwner,
    fr.OwnerReputation,
    fr.AnswerId,
    fr.AnswerScore,
    fr.AnswerOwner,
    fr.AnswererReputation,
    fr.UpVotes,
    fr.DownVotes,
    fr.CountTitleBodyTagEdits,
    fr.LastEditDate,
    fr.CommentCount,
    fr.UserComments,
    fr.Commenters,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.OriginalQuestionId,
    fr.IsDuplicate,
    (
      'Q: ' || fr.Title || ' (Score: ' || cast(fr.QuestionScore as varchar) || ', Views: ' || cast(fr.ViewCount as varchar) || ') - '
      || 'Asked by ' || coalesce(fr.QuestionOwner, 'Unknown') || ' (Rep: ' || coalesce(cast(fr.OwnerReputation as varchar), '0') || ')'
      || (case when fr.IsDuplicate then ' [DUPLICATE of Q#' || coalesce(cast(fr.OriginalQuestionId as varchar), '') || '] ' else ' ' end)
      || 'Top Answer: ' || coalesce(fr.AnswerOwner, 'N/A') || ' (Score: ' || coalesce(cast(fr.AnswerScore as varchar), '0') || ', Up:' || coalesce(cast(fr.UpVotes as varchar), '0') || ', Down:' || coalesce(cast(fr.DownVotes as varchar), '0') || ')'
      || '. Comments (' || coalesce(cast(fr.CommentCount as varchar), '0') || ', Users: ' || coalesce(cast(fr.UserComments as varchar), '0') || '): ' || coalesce(fr.Commenters, 'No comments')
      || '. Edits: ' || coalesce(cast(fr.CountTitleBodyTagEdits as varchar), '0') || ' (Last edit: ' || coalesce(cast(fr.LastEditDate as varchar), 'Never') || ')'
      || '. Owner Badges - Gold: ' || coalesce(cast(fr.GoldBadges as varchar), '0') || ', Silver: ' || coalesce(cast(fr.SilverBadges as varchar), '0') || ', Bronze: ' || coalesce(cast(fr.BronzeBadges as varchar), '0')
    ) as FullDescription
from FinalResultSet fr
where fr.OwnerReputation > 1000
order by fr.QuestionScore desc, fr.ViewCount desc, fr.AnswerScore desc
fetch first 50 rows only;