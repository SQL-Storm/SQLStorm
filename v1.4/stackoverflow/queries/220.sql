with
base as (
  select p.Id, p.Title, p.Tags, p.CreationDate, p.LastActivityDate, p.OwnerUserId
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (cast('2024-10-01' as date) - interval '90 day')
),
up as (
  select v.PostId, count(*) as UpVotes
  from Votes v
  join VoteTypes vt on v.VoteTypeId = vt.Id
  where vt.Name in ('UpMod','AcceptedByOriginator','ModeratorReview')
  group by v.PostId
),
down as (
  select v.PostId, count(*) as DownVotes
  from Votes v
  join VoteTypes vt on v.VoteTypeId = vt.Id
  where vt.Name = 'DownMod'
  group by v.PostId
),
cmt as (
  select PostId, count(*) as CommentCount
  from Comments
  group by PostId
),
link as (
  select PostId, count(*) as LinkCount
  from PostLinks
  group by PostId
),
net as (
  select b.Id,
         b.Title,
         b.Tags,
         b.CreationDate,
         b.LastActivityDate,
         b.OwnerUserId,
         coalesce(u.UpVotes,0) as UpVotes,
         coalesce(d.DownVotes,0) as DownVotes,
         coalesce(c.CommentCount,0) as CommentCount,
         coalesce(l.LinkCount,0) as LinkCount,
         (coalesce(u.UpVotes,0) - coalesce(d.DownVotes,0) + coalesce(l.LinkCount,0) - coalesce(c.CommentCount,0)) as NetScore
  from base b
  left join up u on u.PostId = b.Id
  left join down d on d.PostId = b.Id
  left join cmt c on c.PostId = b.Id
  left join link l on l.PostId = b.Id
),
top_day as (
  select NetScore, Id as PostId, Title, Tags, CreationDate, LastActivityDate, OwnerUserId, CommentCount, LinkCount,
         row_number() over (partition by CAST(CreationDate AS date) order by NetScore desc, LastActivityDate desc) as rn
  from net
),
selectable as (
  select t.PostId, t.Title, t.Tags, t.CreationDate, t.LastActivityDate, t.OwnerUserId, t.CommentCount, t.LinkCount, t.NetScore,
         (case when t.Tags is null then cast(array[] as text[])
               else (select array_agg(trim(x)) from unnest(string_to_array(substr(t.Tags, 2, length(t.Tags) - 2), '><')) as x)
          end) as TagNames
  from top_day t
  where t.rn = 1
),
final1 as (
  select s.PostId as post_id, s.Title as title, s.TagNames as tag_names, s.NetScore as net_score,
         s.CommentCount as comment_count, s.LinkCount as link_count, u.DisplayName as owner_display_name, s.CreationDate as creation_date
  from selectable s
  join Users u on u.Id = s.OwnerUserId
  where s.NetScore > (select avg(NetScore) from selectable)
  order by s.NetScore desc
  limit 70
),
final2 as (
  select s.PostId as post_id, s.Title as title, s.TagNames as tag_names, s.NetScore as net_score,
         s.CommentCount as comment_count, s.LinkCount as link_count, u.DisplayName as owner_display_name, s.CreationDate as creation_date
  from selectable s
  join Users u on u.Id = s.OwnerUserId
  where cast(s.CreationDate as date) = cast('2024-10-01' as date)
  order by s.CommentCount desc
  limit 30
)
select * from (
  select * from final1
  union all
  select * from final2
) as combined
order by net_score desc
limit 100;