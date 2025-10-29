-- {"query": "2031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1396} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        coalesce(tp.CumulativeCount, 0) as ParentTagCount
    from
        Tags t
    left join Lateral (
        select sum(p.ViewCount) as CumulativeCount
        from Posts p
        where p.PostTypeId = 1 -- questions only
          and p.Tags like concat('%<', t.TagName, '>%')
    ) tp on true
    where t.IsModeratorOnly = 0

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.IsModeratorOnly,
        t2.IsRequired,
        rtc.ParentTagCount + coalesce(tp2.CumulativeCount, 0)
    from
        Tags t2
    join RecursiveTagCounts rtc on rtc.Id <> t2.Id
    left join Lateral (
        select sum(p.ViewCount) as CumulativeCount
        from Posts p
        where p.PostTypeId = 1
          and p.Tags like concat('%<', t2.TagName, '>%')
    ) tp2 on true
    where t2.IsModeratorOnly = 0
      and t2.Id > rtc.Id
)
, TopQuestionAnswers AS (
    select 
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score as QuestionScore,
        p.ViewCount,
        count(a.Id) filter (where a.Score > 0) as PositiveAnswersCount,
        count(a.Id) filter (where a.Score <= 0) as NonPositiveAnswersCount,
        max(a.CreationDate) as LastAnswerDate,
        max(a.Score) as MaxAnswerScore
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
      and p.Score >= 5
      and p.ViewCount >= 100
    group by p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount
)
, UserBadgeStats AS (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
)
, VoteAggregates AS (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
)
, RankedPosts AS (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        va.UpVotes,
        va.DownVotes,
        va.FavoriteVotes,
        va.TotalVotes,
        row_number() over (partition by p.PostTypeId order by p.Score desc, va.UpVotes desc) as RankByScore,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate desc) as RankByDateDesc
    from Posts p
    left join VoteAggregates va on va.PostId = p.Id
)
select
    q.Title as QuestionTitle,
    u.DisplayName as AuthorName,
    q.Score as QuestionScore,
    q.ViewCount,
    q.PositiveAnswersCount,
    q.NonPositiveAnswersCount,
    q.MaxAnswerScore,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    case
        when q.PositiveAnswersCount > 5 and q.Score > 20 then 'Hot Question'
        when q.ViewCount > 1000 and q.Score > 10 then 'Trending'
        else 'Normal'
    end as QuestionStatus,
    concat(
        'Tags: ',
        coalesce(
            string_agg(distinct tg.TagName, ', ') filter (where tg.TagName is not null), 
            'No Tags'
        )
    ) as TagList,
    -- correlated subquery for last comment text of question
    (
        select c.Text
        from Comments c
        where c.PostId = q.QuestionId
        order by c.CreationDate desc
        limit 1
    ) as LastCommentText,
    -- user bio snippet with NULL handling
    coalesce(left(u.AboutMe, 50), 'No About Me') as UserBioSnippet,
    -- time since user last access (in days)
    extract(day from (now() - u.LastAccessDate)) as DaysSinceLastAccess,
    -- existence of accepted answer
    case 
        when pa.AcceptedAnswerId is not null then 'Yes' 
        else 'No' 
    end as HasAcceptedAnswer,
    -- count of close votes from post history
    (
        select count(*)
        from PostHistory ph
        where ph.PostId = q.QuestionId
          and ph.PostHistoryTypeId = 10
    ) as CloseVotesCount
from TopQuestionAnswers q
inner join Users u on u.Id = q.OwnerUserId
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join Posts pa on pa.Id = q.QuestionId
left join Lateral (
    select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.Id = q.QuestionId
) tg on true
left join RankedPosts rp on rp.Id = q.QuestionId
where rp.RankByScore <= 100
order by q.Score desc, q.ViewCount desc
limit 50;