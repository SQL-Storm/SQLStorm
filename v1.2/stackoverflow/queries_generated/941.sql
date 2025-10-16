-- {"query": "941.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1273} 
with RankedAnswers as (
    select 
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank,
        count(*) over (partition by p.ParentId) as TotalAnswers
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 2
),
QuestionStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        u.DisplayName as QuestionOwner,
        coalesce(a.AcceptedAnswerId, -1) as AcceptedAnswerId,
        (select count(*) from Comments c where c.PostId = q.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as DownVotes
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join Posts a on q.AcceptedAnswerId = a.Id
    where q.PostTypeId = 1
),
TopAnswers as (
    select 
        ra.ParentId as QuestionId,
        json_agg(json_build_object(
            'AnswerId', ra.Id,
            'Score', ra.Score,
            'OwnerName', ra.OwnerName,
            'AnswerRank', ra.AnswerRank
        ) order by ra.AnswerRank) as AnswersByRank
    from RankedAnswers ra
    where ra.AnswerRank <= 3
    group by ra.ParentId
),
PostHistorySummary as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        count(*) as HistoryCount,
        max(ph.CreationDate) as LastHistoryDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    group by ph.PostId, ph.PostHistoryTypeId, pht.Name
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
QuestionLinkInfo as (
    select
        q.Id as QuestionId,
        count(distinct pl.Id) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from Posts q
    left join PostLinks pl on q.Id = pl.PostId
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    where q.PostTypeId = 1
    group by q.Id
),
FinalStats as (
    select 
        qs.QuestionId,
        qs.Title,
        qs.CreationDate,
        qs.QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        qs.FavoriteCount,
        qs.CommentCount,
        qs.UpVotes,
        qs.DownVotes,
        qs.Tags,
        qs.QuestionOwner,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        phs.HistoryCount as EditCount,
        phs.LastHistoryDate,
        qli.LinkedCount,
        qli.DuplicateCount,
        ta.AnswersByRank
    from QuestionStats qs
    left join Users u on qs.QuestionOwner = u.DisplayName
    left join UserBadgeCounts ubs on u.Id = ubs.UserId
    left join (
        select PostId, sum(HistoryCount) as HistoryCount, max(LastHistoryDate) as LastHistoryDate
        from PostHistorySummary
        where HistoryTypeName in ('Edit Title','Edit Body','Edit Tags','Rollback Title','Rollback Body','Rollback Tags')
        group by PostId
    ) phs on qs.QuestionId = phs.PostId
    left join QuestionLinkInfo qli on qs.QuestionId = qli.QuestionId
    left join TopAnswers ta on qs.QuestionId = ta.QuestionId
    where qs.ViewCount > 1000 and qs.AnswerCount > 0
)
select
    fs.QuestionId,
    fs.Title,
    fs.CreationDate,
    fs.QuestionScore,
    fs.ViewCount,
    fs.AnswerCount,
    fs.FavoriteCount,
    fs.CommentCount,
    fs.UpVotes,
    fs.DownVotes,
    coalesce(fs.Tags, '') as Tags,
    fs.QuestionOwner,
    coalesce(fs.GoldBadges,0) as GoldBadges,
    coalesce(fs.SilverBadges,0) as SilverBadges,
    coalesce(fs.BronzeBadges,0) as BronzeBadges,
    coalesce(fs.EditCount,0) as EditCount,
    fs.LastHistoryDate,
    coalesce(fs.LinkedCount,0) as LinkedCount,
    coalesce(fs.DuplicateCount,0) as DuplicateCount,
    fs.AnswersByRank,
    case 
        when fs.FavoriteCount > 10 and fs.AnswerCount > 5 then 'Hot'
        when fs.ViewCount > 10000 then 'Popular'
        else 'Normal'
    end as PopularityTier,
    lower(trim(split_part(fs.QuestionOwner, ' ', 1))) || '_user' as OwnerUserNameSlug
from FinalStats fs
order by fs.ViewCount desc, fs.AnswerCount desc, fs.QuestionScore desc
limit 50;