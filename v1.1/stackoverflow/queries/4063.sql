with RecursiveUserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        coalesce(bc.BadgeCount, 0) as BadgeCount,
        coalesce(pc.QuestionCount, 0) as QuestionCount,
        coalesce(ac.AnswerCount, 0) as AnswerCount,
        row_number() over (order by u.Reputation desc, u.Id) as UserRank
    from Users u
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) bc on bc.UserId = u.Id
    left join (
        select OwnerUserId, count(*) as QuestionCount
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) pc on pc.OwnerUserId = u.Id
    left join (
        select OwnerUserId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) ac on ac.OwnerUserId = u.Id
), PostScoresCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        case 
            when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 1
            else 0
        end as HasAcceptedAnswer,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentsCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        case 
            when p.Tags is not null then array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), 1)
            else 0
        end as TagCount
    from Posts p
    where p.PostTypeId in (1,2)
), LatestEditInfo as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.CreationDate as LastEditDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorDisplayName,
        ph.PostHistoryTypeId,
        ph.Comment as EditComment
    from PostHistory ph
    where ph.PostId in (select Id from Posts)
    order by ph.PostId, ph.CreationDate desc
), CombinedUserPostData as (
    select
        u.Id as UserId,
        u.DisplayName as UserName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        ps.CommentsCount,
        ps.UpVotes,
        ps.DownVotes,
        ps.TagCount,
        le.LastEditDate,
        le.EditorUserId,
        le.EditorDisplayName,
        le.PostHistoryTypeId,
        le.EditComment,
        row_number() over (partition by u.Id order by p.Score desc, p.ViewCount desc) as UserPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join PostScoresCTE ps on ps.Id = p.Id
    left join LatestEditInfo le on le.PostId = p.Id
    where u.Reputation > 1000
), TagPopularity as (
    select
        tag,
        count(distinct p.Id) as PostCount,
        avg(p.Score) as AvgScore,
        sum(p.ViewCount) as TotalViews,
        max(p.Score) as MaxScore,
        percentile_cont(0.5) within group (order by p.Score) as MedianScore
    from
        Posts p,
        unnest(
            case when p.Tags is not null then string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><') else array[]::text[] end
        ) as tag
    where p.PostTypeId = 1
    group by tag
    having count(distinct p.Id) > 5
    order by TotalViews desc
), UserBadgeTagAgg as (
    select
        b.UserId,
        lower(b.Name) as BadgeNameLower,
        count(*) as BadgeCount,
        array_agg(distinct lower(t.TagName)) filter (where t.TagName is not null) as BadgeTags
    from Badges b
    left join Tags t on t.TagName = b.Name
    group by b.UserId, lower(b.Name)
), TopActiveUsers as (
    select 
        cua.Id as UserId,
        cua.DisplayName,
        count(ph.Id) as PostHistoryEvents,
        count(v.Id) as VoteCount,
        count(c.Id) as CommentCount,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCreated,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCreated
    from Users cua
    left join PostHistory ph on ph.UserId = cua.Id
    left join Votes v on v.UserId = cua.Id
    left join Comments c on c.UserId = cua.Id
    left join Posts p on p.OwnerUserId = cua.Id
    where cua.Reputation >= 10000
    group by cua.Id, cua.DisplayName
    having count(ph.Id) > 50
    order by PostHistoryEvents desc
    limit 10
)
select distinct on (cupa.UserId)
    cupa.UserId,
    cupa.UserName,
    cupa.Reputation,
    cupa.PostId,
    cupa.PostTypeId,
    cupa.Title,
    cupa.Tags,
    cupa.Score,
    cupa.ViewCount,
    cupa.AnswerCount,
    cupa.FavoriteCount,
    cupa.CommentsCount,
    cupa.UpVotes,
    cupa.DownVotes,
    cupa.TagCount,
    cupa.LastEditDate,
    cupa.EditorUserId,
    cupa.EditorDisplayName,
    cupa.PostHistoryTypeId,
    cupa.EditComment,
    tu.PostHistoryEvents,
    tu.VoteCount,
    tu.CommentCount,
    tu.QuestionsCreated,
    tu.AnswersCreated,
    tp.PostCount as TagPostCount,
    tp.AvgScore as TagAvgScore,
    tp.TotalViews as TagTotalViews,
    tp.MaxScore as TagMaxScore,
    tp.MedianScore as TagMedianScore,
    ubd.BadgeCount,
    string_agg(distinct ubd.BadgesNamed::text, ', ') as BadgesNamed,
    string_agg(distinct bt.tag, ', ') as BadgeTags
from CombinedUserPostData cupa
left join TopActiveUsers tu on tu.UserId = cupa.UserId
left join lateral (
    select tp_inner.*
    from TagPopularity tp_inner
    cross join lateral (
        select unnest(string_to_array(substring(cupa.Tags from 2 for char_length(cupa.Tags) - 2), '><')) as t
    ) tlist
    where tp_inner.tag = tlist.t
    order by random()
    limit 1
) tp on true
left join lateral (
    select
        ubt.UserId,
        sum(ubt.BadgeCount) as BadgeCount,
        array_agg(distinct ubt.BadgeNameLower) as BadgesNamed
    from UserBadgeTagAgg ubt
    where ubt.UserId = cupa.UserId
    group by ubt.UserId
) ubd on ubd.UserId = cupa.UserId
left join lateral (
    select distinct bt.tag
    from UserBadgeTagAgg ubt2
    cross join lateral unnest(coalesce(ubt2.BadgeTags, array[]::text[])) as bt(tag)
    where ubt2.UserId = cupa.UserId
) bt on true
where cupa.UserPostRank <= 3 
and (cupa.PostTypeId = 1 or (cupa.PostTypeId = 2 and exists (
    select 1 from Posts q where q.Id = cupa.PostId and q.ParentId = cupa.PostId
)))
group by
    cupa.UserId,
    cupa.UserName,
    cupa.Reputation,
    cupa.PostId,
    cupa.PostTypeId,
    cupa.Title,
    cupa.Tags,
    cupa.Score,
    cupa.ViewCount,
    cupa.AnswerCount,
    cupa.FavoriteCount,
    cupa.CommentsCount,
    cupa.UpVotes,
    cupa.DownVotes,
    cupa.TagCount,
    cupa.LastEditDate,
    cupa.EditorUserId,
    cupa.EditorDisplayName,
    cupa.PostHistoryTypeId,
    cupa.EditComment,
    tu.PostHistoryEvents,
    tu.VoteCount,
    tu.CommentCount,
    tu.QuestionsCreated,
    tu.AnswersCreated,
    tp.PostCount,
    tp.AvgScore,
    tp.TotalViews,
    tp.MaxScore,
    tp.MedianScore,
    ubd.BadgeCount,
    ubd.BadgesNamed,
    bt.tag
order by cupa.UserId, cupa.Score desc;